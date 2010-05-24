require 'typhoeus'
require 'nokogiri'

class TwitterPhoto
  attr_accessor :username, :thumb, :date, :tweet, :url
  
  TWITPIC_URL    = 'http://twitpic.com'
  TWEETPHOTO_URL = 'http://tweetphotoapi.com/api/tpapi.svc/json/usernames/'
  YFROG_URL      = 'http://yfrog.com/froggy.php'
  TWITGOO_URL    = 'http://twitgoo.com/api/username/timeline/'
  
  
  def initialize(thumb=nil, tweet='No tweet for this photo', date=nil, url=nil, username=nil)
    date = date.strip
    dmatch = date.match(/\sago\b/i)
    @username  = username
    @thumb = thumb
    @tweet = tweet.strip
    @date  = dmatch.nil? ?  DateTime.parse(date).to_s : DateTime.time_ago_to_date(date).to_s rescue @date = date
    @url   = url
    @tweet = "No tweet for this photo." if @tweet.blank?
  end
  
  # Find all TwitterPhoto objects with the username of the given value. Example: TwitterPhoto.find_by_username('bookis')
  def self.find_by_username(username)
    found = []
    ObjectSpace.each_object(TwitterPhoto) { |o|
      found << o if o.username == username
    }
    found.sort_by {|x| x.date}
  end
  
  # Fetch photos from Twitpic, yFrog, Twitgoo, and TweetPhoto.
  # @example Find photo by bookis only from yfrog and twitpic
  #   TwitterPhoto.get_photos_by('bookis', :tweetphoto => false, :yfrog => true, :twitpic => true, :twitgoo => false)
  # @option options [true, false] :tweetphoto default true
  # @option options [true, false] :twitpic default true
  # @option options [true, false] :yfrog default true
  # @option options [true, false] :twitgoo default true
  # @return [TwitterPhoto] A collection of TwitterPhoto objects will be returned
  @param :username
  def self.get_photos_by(username, options={})
    @pix = []
    hydra = Typhoeus::Hydra.new
    
    twitpic_request  = Typhoeus::Request.new("#{TWITPIC_URL}/photos/#{username}", :timeout => 5000)
    twitpic_request.on_complete do |response|
      twitpics = Nokogiri.parse(response.body)
      twitpics.xpath("//div[@class='profile-photo-img']/a").each do |row|
        url = row[:href]
        twitpic_request = Typhoeus::Request.new("#{TWITPIC_URL}#{url}", :timeout => 5000)
        twitpic_request.on_complete do |twitpic|
          begin
            twitpic = Nokogiri.parse(twitpic.body)
            # pic = []
            TwitterPhoto.new(
                             "#{TWITPIC_URL}/show/thumb#{url}.jpg",
                             twitpic.xpath("//div/div[@id='view-photo-caption']").text,
                             twitpic.xpath("//div/div[@id='photo-info']").text,
                             twitpic.at_xpath("//img[@class='photo']")[:src],
                             username
                            )
          rescue
          end
        end
        hydra.queue twitpic_request
      end
    end
    
    yfrog_request  = Typhoeus::Request.new(YFROG_URL, :params => {:username => username}, :timeout => 5000)
    yfrog_request.on_complete do |response|
      yfrogs = Nokogiri.parse(response.body)
      yfrogs.xpath("//div[@class='timeline_entry']").each do |row|
         url = row.at_xpath("div/div[@class='thumbtweet' ]/a")[:href]
         yfrog_request = Typhoeus::Request.new(url, :timeout => 5000)
         yfrog_request.on_complete do |yfrog|
           begin
              yfrog = Nokogiri.parse(yfrog.body)
              TwitterPhoto.new(
                              yfrog.at_xpath("//meta[@property='og:title']").attributes['content'].to_s + '.th.jpg',
                              yfrog.at_xpath("///div[@class='twittertweet']/div/div/div").text, 
                              yfrog.at_xpath("///div[@class='twittertweet']/div/div/div/div").text,
                              yfrog.at_xpath("//img[@id='main_image']")[:src],
                              username
                              )
            rescue
            end
         end
         hydra.queue yfrog_request
       end
    end
    
    tweetphoto_request = Typhoeus::Request.new("#{TWEETPHOTO_URL}#{username}", :timeout => 5000)
    tweetphoto_request.on_complete do |response|
      if response.code == 200
        tweetphoto_id = JSON.parse(response.body)["Id"]
        tweetphoto_username_request = Typhoeus::Request.new("#{TWEETPHOTO_URL}#{tweetphoto_id}/photos", :timeout => 5000)
        tweetphoto_username_request.on_complete do |tweetphoto_username|
          tweetphotodata = JSON.parse(tweetphoto_username.body)
          tweetphotodata['List'].each do |tweetphoto|
            TwitterPhoto.new(
                             tweetphoto['ThumbnailUrl'],
                             tweetphoto['Message'],
                             tweetphoto['UploadDateString'],
                             tweetphoto['MediumImageUrl'],
                             username
                            )
          end
        end
        hydra.queue tweetphoto_username_request
      end
    end
     
    twitgoo_request  = Typhoeus::Request.new("#{TWITGOO_URL}#{username}", :params => {:format => 'json'}, :timeout => 5000)
    twitgoo_request.on_complete do |response|
      if response.code == 200
        twitgoo = JSON.parse(response.body)
        twitgoo['media'].each do |twit|
          TwitterPhoto.new(
                           twit['thumburl'],
                           twit['text'],
                           twit['created_at'],
                           twit['imageurl'],
                           username
                          )
        end
      end
    end
    
    hydra.queue yfrog_request unless options[:yfrog] == false
    hydra.queue tweetphoto_request unless options[:tweetphoto] == false
    hydra.queue twitpic_request unless options[:twitpic] == false
    hydra.queue twitgoo_request unless options[:twitgoo] == false
    hydra.run
    
    TwitterPhoto.find_by_username(username)
      
  end
end

private

module TimeMod
  def time_ago_to_date(tweet_date)
     date = DateTime.now
     intervals = %w(year month week day hour min minute second)
     intervals.each do |interval|
       number = tweet_date.match(/([\d*]+)\s#{interval}/i)
       if number
         interval = 'minutes' if interval == 'min'
         date = date - number[1].to_i.try(interval)
       end
     end
     date
   end
end

class DateTime
  extend TimeMod
end