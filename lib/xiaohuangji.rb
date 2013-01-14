#encoding: utf-8
#Copyright (c) 2013 zhhailon <zhhailon@gmail.com>

require 'xiaohuangji/simisimi'

module Xiaohuangji
  def self.chat(msg='')
    SimiSimi.new.chat msg
  end
end
