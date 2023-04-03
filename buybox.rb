# frozen_string_literal: true

require 'watir'
require 'csv'

MAX_RESULT_PAGES = 5
MINIMUM_RATING_COUNT = 1000
MAX_BUYBOX_COUNT = 10

PRODUCT_PARSERS = {
  asin: ->(product) { product.data_asin },
  title: ->(product) { product.div(class: 's-title-instructions-style').text },
  rating_count: lambda { |product|
    product.span(class: 's-underline-text')
           .text.match(/([\d,]+)/)
           .captures.first
           .delete(',').to_i
  },
  buybox_count: ->(product) {},
  url: ->(product) { product.a(class: 'a-link-normal').href }
}.freeze

url = ARGV[0]
raise ArgumentError, 'No URL provided' unless url

puts 'Starting web browser...'
browser = Watir::Browser.new :chrome, headless: true
product_browser = Watir::Browser.new :chrome, headless: true

results = []
begin
  puts 'Opening search results...'
  browser.goto url

  MAX_RESULT_PAGES.times do
    result_list = browser.div(class: 's-result-list')
    result_list.wait_until(&:exists?)

    products = result_list.children.reject { |r| r.data_asin.empty? }
    products.each do |product_html|
      product = PRODUCT_PARSERS.transform_values do |parser|
        parser.call(product_html)
      end

      next unless product[:rating_count] >= MINIMUM_RATING_COUNT

      puts "#{product[:asin]}'s rating count is above #{MINIMUM_RATING_COUNT} (#{product[:rating_count]})"
      product_browser.goto product[:url]

      buybox_see_all = product_browser.span(id: 'buybox-see-all-buying-choices')
      next unless buybox_see_all.exists?

      buybox_see_all.click

      puts "#{product[:asin]}'s buybox is disabled...'"
      buybox_count = product_browser.span(id: 'aod-filter-offer-count-string').text.to_i
      next unless buybox_count <= MAX_BUYBOX_COUNT

      product[:buybox_count] = buybox_count

      puts "#{product[:asin]}'s seller count is less than #{MAX_BUYBOX_COUNT} (#{product[:buybox_count]})"
      results << product
    end

    next_link = browser.a(class: 's-pagination-next')
    break unless next_link.exists?

    puts 'Opening next results page...'
    browser.goto next_link.href
  end
rescue StandardError => e
  warn 'An error ocurred, saving log to error.json...'
  File.write('error.json',
             JSON.dump({
                         error: {
                           message: e.message,
                           backtrace: e.backtrace
                         },
                         search_params: {
                           search_url: url,
                           current_url: browser.url,
                           max_result_pages: MAX_RESULT_PAGES,
                           minimum_rating_count: MINIMUM_RATING_COUNT,
                           max_buybox_count: MAX_BUYBOX_COUNT
                         }
                       }))
ensure
  product_browser.close
  browser.close

  if results.empty?
    warn 'No product found.'
  else
    puts 'Saving products to csv file...'
    CSV.open('results.csv', 'wb', write_headers: true, headers: PRODUCT_PARSERS.keys) do |csv|
      results.each { |review| csv << review }
    end
  end
end
