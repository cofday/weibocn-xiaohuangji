#encoding: utf-8
#Copyright (c) 2013 zhhailon <zhhailon@gmail.com>

require 'rest-client'
require 'nokogiri'
require 'sqlite3'
require 'xiaohuangji'

module WeiboSimi
  class Client

    def initialize(username, password)
      @username = username
      @password = password
      @weibo_url = 'http://weibo.cn/pub'
      @login_url = 'http://login.weibo.cn/login/'
      @url = "#{@login_url}?ns=1&revalid=2&backURL=http%3A%2F%2Fweibo.cn%2F&backTitle=%D0%C2%C0%CB%CE%A2%B2%A9&vt="
      @headers = { 
        'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; rv:18.0) Gecko/20100101 Firefox/18.0',
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3',
        'Accept-Encoding' => 'gzip, deflate',
        'DNT' => '1',
        'Connection' => 'keep-alive'
      }
      @qa = []
      begin
        create_db
      rescue Exception => e
        puts '++++++ DB error ++++++'
        puts e
        puts '++++++ DB error ++++++'
        open_db
      end
    end

    def get_login_url
      begin
        res = RestClient.get @weibo_url
        code = res.encoding
        doc = Nokogiri::HTML res, nil, 'utf-8'
        charset = doc.meta_encoding
        a = doc.xpath('//a').first
        url = a['href']
        url
      rescue Exception => e
        puts '@@@@@@ mainpage error @@@@@@'
        puts e
        puts '@@@@@@ mainpage error @@@@@@'
      end
      
    end

    def get_login_post_info(url)
      begin
        res = RestClient.get URI.encode(url), @headers 
        doc = Nokogiri::HTML res, nil, 'utf-8' 
        action = doc.xpath('//form/@action').first.content
        password = doc.xpath('//input[@type="password"]/@name').first.content
        backURL = doc.xpath('//input[@name="backURL"]/@value').first.content
        backTitle = doc.xpath('//input[@name="backTitle"]/@value').first.content
        vk = doc.xpath('//input[@name="vk"]/@value').first.content
        submit = doc.xpath('//input[@name="submit"]/@value').first.content
        { action: action, password: password, backURL: backURL, backTitle: backTitle, vk: vk, submit: submit }
      rescue Exception => e
        puts '****** RC error ******'
        puts e.class
        puts e.backtrace
        puts '****** RC error ******'
      end
    end

    def login
      url = get_login_url
      post_info = get_login_post_info url
      post_data = {
        'mobile' => @username,
        post_info[:password] => @password,
        'remember' => 'on',
        'backURL' => URI.encode(post_info[:backURL]),
        'backTitle' => URI.encode(post_info[:backTitle]),
        'vk' => post_info[:vk],
        'submit' => URI.encode(post_info[:submit]),
        'encoding' => 'utf-8'
      }
      url = "#{@login_url}#{post_info[:action]}"
      res = Net::HTTP.post_form URI(url), post_data
      res = RestClient::Response.create res.body, res, method: :get
      res = res.follow_redirection
      @gsid_CTandWM = res.cookies['gsid_CTandWM']
      @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}"
      doc = Nokogiri::HTML res, nil, 'utf-8' 
      url = doc.xpath('//a/@href').first.content
      res = RestClient.get url, @headers
      @weibo_uid = res.cookies['_WEIBO_UID']
      @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
      res
    end

    def reply_to_at
      at_url = 'http://weibo.cn/at/weibo'
      @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
      at_res = RestClient.get at_url, @headers
      at_doc = Nokogiri::HTML at_res, nil, 'utf-8'
      urls = at_doc.xpath('//a[starts-with(text(),"评论[")]/@href')
      urls.each do |url|
        url = url.content
        unless has_url_in_db? url
          puts "New @"
          res = RestClient.get url, @headers
          doc = Nokogiri::HTML res, nil, 'utf-8'
          content = doc.xpath('//span[@class="ctt"]').first
          question = ''
          content.children.each { |c| question += c.content if c.is_a? Nokogiri::XML::Text }
          question = question[1..-1] if question.start_with? ':'
          puts "Question #{question.encoding} :::: '#{question.strip}'"
          answer = Xiaohuangji.chat question.strip
          answer = answer_question_in_db question if answer.nil?
          if answer.nil?
            puts 'Will try to reply later...'
            return
          end
          puts "Answer  #{answer.encoding}  :::: '#{answer}'"
          srcuid = doc.xpath('//input[@name="srcuid"]/@value').first.content
          id = doc.xpath('//input[@name="id"]/@value').first.content
          rl = doc.xpath('//input[@name="rl"]/@value').first.content
          post_data = {
            'srcuid' => srcuid,
            'id' => id,
            'rl' => rl,
            'content' => answer
          }
          action = doc.xpath('//form[@method="post"]/@action').first.content
          reply_url = "http://weibo.cn#{action}"
          uri = URI reply_url
          @headers['Referer'] = url
          @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
          req = Net::HTTP::Post.new "#{uri.path}?#{uri.query}"
          req.set_form_data post_data
          @headers.each { |k, v| req[k.to_s] = v.to_s }
          res = Net::HTTP.start(uri.hostname, uri.port) do |http|
            http.request req
          end

          if res.code == '302'
            puts "Success #{res}"
            record_qa id, question, answer 
          else
            puts "Failed #{res}" if res.code != '302'
          end
        end
      end
    end
    
    def reply_to_comment
      comment_url = 'http://weibo.cn/msg/comment/receive'
      @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
      res = RestClient.get comment_url, @headers
      doc = Nokogiri::HTML res, nil, 'utf-8'
      new_spans = doc.xpath('//span[text()="[新]"]')
      return if new_spans.empty?
      new_spans.each do |ns|
        comment = ''
        puts 'New Comment'
        comment_node = ns
        comment_node = comment_node.next until comment_node['class'] == 'ctt'
        comment_node.children.each { |c| comment += c.content if c.is_a? Nokogiri::XML::Text }
        puts "Comment #{comment.encoding} :::: '#{comment.strip}'"
        answer = answer_question comment.strip
        answer = '呵呵' if answer.nil?
        puts "Answer  #{answer.encoding}  :::: '#{answer}'"
        reply_node = comment_node
        reply_node = reply_node.next until reply_node['class'] == 'cc'
        reply_url = 'http://weibo.cn' + reply_node.children[0]['href']
        res = RestClient.get reply_url, @headers
        doc = Nokogiri::HTML res, nil, 'utf-8'
        cmtid = doc.xpath('//input[@name="cmtid"]/@value').first.content
        id = doc.xpath('//input[@name="id"]/@value').first.content
        rl = doc.xpath('//input[@name="rl"]/@value').first.content
        post_data = {
          'cmtid' => cmtid,
          'id' => id,
          'rl' => rl,
          'content' => answer
        }
        action = doc.xpath('//form[@method="post"]/@action').first.content
        reply_url = "http://weibo.cn#{action}"
        uri = URI reply_url
        @headers['Referer'] = comment_url
        @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
        req = Net::HTTP::Post.new "#{uri.path}?#{uri.query}"
        req.set_form_data post_data
        @headers.each { |k, v| req[k.to_s] = v.to_s }
        res = Net::HTTP.start(uri.hostname, uri.port) do |http|
          http.request req
        end
        if res.code == '302'
          puts "Success #{res}"
          record_qa '', comment, answer 
        else
          puts "Failed #{res}" if res.code != '302'
        end
      end
    end
    
    def reply_to_at_comment
      comment_url = 'http://weibo.cn/at/comment'
      @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
      res = RestClient.get comment_url, @headers
      doc = Nokogiri::HTML res, nil, 'utf-8'
      new_spans = doc.xpath('//span[text()="[新]"]')
      return if new_spans.empty?
      new_spans.each do |ns|
        comment = ''
        puts 'New @ Comment'
        comment_node = ns
        comment_node = comment_node.next until comment_node['class'] == 'ctt'
        comment_node.children.each { |c| comment += c.content if c.is_a? Nokogiri::XML::Text }
        comment = comment[2..-1].strip if comment.strip.start_with? '回复'
        comment = comment[1..-1].strip if comment.strip.start_with? ':'
        puts "Comment #{comment.encoding} :::: '#{comment.strip}'"
        answer = answer_question comment.strip
        answer = '呵呵' if answer.nil?
        puts "Answer  #{answer.encoding}  :::: '#{answer}'"
        reply_node = comment_node
        reply_node = reply_node.next until reply_node['class'] == 'cc'
        reply_url = 'http://weibo.cn' + reply_node.children[0]['href']
        res = RestClient.get reply_url, @headers
        doc = Nokogiri::HTML res, nil, 'utf-8'
        cmtid = doc.xpath('//input[@name="cmtid"]/@value').first.content
        id = doc.xpath('//input[@name="id"]/@value').first.content
        rl = doc.xpath('//input[@name="rl"]/@value').first.content
        post_data = {
          'cmtid' => cmtid,
          'id' => id,
          'rl' => rl,
          'content' => answer
        }
        action = doc.xpath('//form[@method="post"]/@action').first.content
        reply_url = "http://weibo.cn#{action}"
        uri = URI reply_url
        @headers['Referer'] = comment_url
        @headers[:cookie] = "gsid_CTandWM=#{@gsid_CTandWM}; _WEIBO_UID=#{@weibo_uid}"
        req = Net::HTTP::Post.new "#{uri.path}?#{uri.query}"
        req.set_form_data post_data
        @headers.each { |k, v| req[k.to_s] = v.to_s }
        res = Net::HTTP.start(uri.hostname, uri.port) do |http|
          http.request req
        end
        if res.code == '302'
          puts "Success #{res}"
          record_qa '', comment, answer 
        else
          puts "Failed #{res}" if res.code != '302'
        end
      end
    end
    
    def write_qa_to_db
      while qa = @qa.shift
        p qa
        @db.execute 'insert into qa values ( ?, ? , ? )', qa[:id], qa[:question], qa[:answer]
      end
    end

    private
      def record_qa(id, question, answer)
        new_qa = { id: id, question: question, answer: answer }
        @qa << new_qa
      end
    
      def answer_question(question)
        answer = Xiaohuangji.chat question.strip
        answer = answer_question_in_db question if answer.nil?
        answer
      end

      def create_db
        @db = SQLite3::Database.new "db/simisimi.db"
        rows = @db.execute <<-SQL
        create table qa (
          id varchar(10),
          question varchar(30) not null,
          answer varchar(30) not null                        
          )
        SQL
      end

      def open_db
        @db = SQLite3::Database.new "db/simisimi.db"
      end

      # For checking at messages
      def get_weibo_id(url)
        URI.parse(url).path[9..-1]
      end
      
      # For checking at messages
      def has_url_in_db?(url)
        id = get_weibo_id url
        sql = 'select * from qa where id="%s"' % id
        !@db.execute(sql).empty?
      end

      def answer_question_in_db(question)
        puts 'Same question exists in db.'
        sql = 'select answer from qa where question="%s"' % question
        answers = @db.execute(sql).map { |a| a[0] }
        answers.compact.shuffle.first
      end

  end
end
