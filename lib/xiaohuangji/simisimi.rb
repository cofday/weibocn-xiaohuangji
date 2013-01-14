#encoding: utf-8
#Copyright (c) 2013 zhhailon <zhhailon@gmail.com>

require 'open-uri'
require 'json'

$try_times = 0
module Xiaohuangji
  class SimiSimi
    def initialize
      f = open 'http://www.simsimi.com/talk.htm'
      self.chat_cookie = f.meta['set-cookie'].split('; ', 2)[0]
      self.chat_url = 'http://www.simsimi.com/func/req?lc=ch&msg=%s'
    end

    def chat(msg)
      $try_times += 1
      unless msg.nil? or msg.empty?
        puts "#{$try_times} try to connect SimiSimi"
        f = open(URI.encode(chat_url % msg), 
          'Host-Agent' => 'Mozilla/5.0 (Windows NT 6.1; rv:18.0) Gecko/20100101 Firefox/18.0',
          'Accept' => 'applicatoin/json, text/javascript, */*; q=0.01',
          'Accept-Language' => 'zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3',
          'Accept-Encoding' => 'gzip, deflate',
          'DNT' => '1',
          'Referer' => 'http://www.simisimi.com/talk.html?lc=ch',
          'Cookie'  => chat_cookie)
        res = JSON.parse f.read
        ans = res['response']
        begin
          cookie = f.meta['set-cookie'].split('; ', 2)[0]
          self.chat_cookie = cookie
        rescue Exception => e
        ensure
          if ans.nil?
            if $try_times < 4
              Xiaohuangji.chat msg
            else
              $try_times = 0
              return nil
            end
          elsif ans.include? 'Unauthorized access!. In this program(site, app), the SimSimi API is being used illegally. Please contact us. http://developer.simsimi.com'
            $try_times = 0
            return nil
          else
            $try_times = 0
            return ans
          end
        end
      else
        nil
      end
    end

    private
      def chat_cookie
        @chat_cookie
      end

      def chat_cookie=(cookie='')
        @chat_cookie = cookie
      end

      def chat_url
        @chat_url
      end

      def chat_url=(url='')
        @chat_url = url
      end
  end
end
