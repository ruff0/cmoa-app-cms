include Rails.application.routes.url_helpers # brings ActionDispatch::Routing::UrlFor
include ActionView::Helpers::TagHelper
require "#{Rails.root}/lib/feedzirra/vimeo"
require "#{Rails.root}/app/helpers/application_helper"
include ApplicationHelper

namespace :feeds do
  desc 'Parse news and video feeds and generate HTML pages'
  task :generate => :environment do
    # Setup S3
    s3 = AWS::S3.new(
      :access_key_id => CMOA::Application.config.paperclip_defaults[:s3_credentials][:access_key_id],
      :secret_access_key => CMOA::Application.config.paperclip_defaults[:s3_credentials][:secret_access_key]
    )
    bucket = s3.buckets[CMOA::Application.config.paperclip_defaults[:s3_credentials][:bucket]]

    # ********
    # Get News
    # ********
    puts 'Starting news'

    # Parse feeds
    puts '- Parsing RSS feeds'
    feed_urls = ['http://blog.cmoa.org/feed', 'http://director.cmoa.org/feed']
    feeds = Feedzirra::Feed.fetch_and_parse(feed_urls)

    # Join entries from both news feeds and sort by date
    entries = feeds['http://blog.cmoa.org/feed'].entries.concat(feeds['http://director.cmoa.org/feed'].entries)
    entries.sort! { |x,y| y.published <=> x.published }

    # Render feed template
    puts '- Rendering HTML'
    localFilename = "#{Rails.root}/tmp/news.html"
    render_template("feeds/news.html.erb", localFilename, {
      :entries => entries
    })

    # Upload to S3
    puts '- Uploading to S3'
    bucket.objects['feeds/news.html'].write(:file => localFilename, :acl => :public_read)
    puts '- Finished news'

    # **********
    # Get Videos
    # **********
    puts "\nStarting videos"

    # Parse feed
    puts '- Parsing RSS feed'
    Feedzirra::Feed.add_feed_class Feedzirra::Parser::Vimeo
    feed = Feedzirra::Feed.fetch_and_parse('http://vimeo.com/cmoa/videos/rss')

    # Render feed template
    puts '- Rendering HTML'
    localFilename = "#{Rails.root}/tmp/videos.html"
    render_template("feeds/videos.html.erb", localFilename, {
      :entries => feed.entries
    })

    # Upload to S3
    puts '- Uploading to S3'
    bucket.objects['feeds/videos.html'].write(:file => localFilename, :acl => :public_read)
    puts '- Finished videos'

    puts "\nDone"
  end
end

def render_template(template, outputFilename, variables)
  av = ActionView::Base.new(Rails.root.join('app', 'views'))
  av.assign(variables)
  f = File.new(outputFilename, 'w')
  f.puts(av.render(:template => template, :layout => 'layouts/feed'))
  f.close
end