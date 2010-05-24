class Date
  def time_ago_to_date(tweet_date)
     date = Time.now
     intervals = %w(year week day hour min minute second)
     intervals.each do |interval|
       number = tweet_date.match(/([\d*]+)\s#{interval}/i)[1]
       interval = 'minutes' if interval == 'min'
       date = date - number.try(interval)
     end
     date
   end
end