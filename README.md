Weibo.cn Xiaohuangji
=============

可以在微博上關注我 http://weibo.com/u/3217703535

### How it works
模擬[新浪微博](http://weibo.cn)的網頁操作，得到at、評論的信息；獲取[SimiSimi](http://simisimi.com)的回答；Post到新浪微博；成功！！

### How to run it
```ruby
f = WeiboSimi::Client.new 'your_weibo_account', 'password'
# Login to weibo.cn
f.login
# Reply to comments
f.reply_to_comment
# Reply to @ comments
f.reply_to_at_comment
# Reply to @ messages
f.reply_to_at
```

### Contribute
Just fork and pull request.

This project use rest-client and Net::HTTP at the same time since I'm not so familiar with rest-client but want to try it in this project. It's awkward and I hope some one can fix it.


