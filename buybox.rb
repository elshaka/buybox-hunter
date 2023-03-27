require 'watir'
require 'csv'
require 'pry'

MAX_RESULT_PAGES = 5
MINIMUM_RATING_COUNT = 1000
MAX_BUYBOX_COUNT = 10

PRODUCT_PARSERS = {
  asin: ->(product) { product.data_asin },
  title: ->(product) { product.div(class: 's-title-instructions-style').text },
  rating_count: ->(product) { product.span(class: 's-underline-text').text.match(/([\d,]+)/).captures.first.delete(',').to_i },
  buybox_count: ->(product) { },
  url: ->(product) { product.a(class: 'a-link-normal').href }
}

url = ARGV[0]
raise ArgumentError.new 'No URL provided' unless url

puts 'Starting web browser...'
browser = Watir::Browser.new :chrome, headless: true
product_browser = Watir::Browser.new :chrome, headless: true

puts 'Opening search results...'
browser.goto url

results = []
begin
  MAX_RESULT_PAGES.times do
    result_list = browser.div(class: 's-result-list')
    result_list.wait_until(&:exists?)

    products = result_list.children.select { |r| !r.data_asin.empty? }
    products.each do |product_html|
      product = PRODUCT_PARSERS.each_with_object({}) do |(field, parser), product|
        product[field] = parser.call(product_html)
      end

      next unless product[:rating_count] >= MINIMUM_RATING_COUNT

      puts "#{product[:asin]}'s rating count is above #{MINIMUM_RATING_COUNT} (#{product[:rating_count]}), opening product page..."
      product_browser.goto product[:url]

      buybox_see_all = product_browser.span(id: 'buybox-see-all-buying-choices')
      next unless buybox_see_all.exists?
      buybox_see_all.click

      puts "#{product[:asin]}'s buybox is disabled...'"
      buybox_count = product_browser.span(id: 'aod-filter-offer-count-string').text.to_i
      next unless buybox_count <= MAX_BUYBOX_COUNT
      product[:buybox_count] = buybox_count

      puts "#{product[:asin]}'s seller count is less than #{MAX_BUYBOX_COUNT} (#{product[:buybox_count]}), adding to results..."
      results << product
    end

    next_link = browser.a(class: 's-pagination-next')
    break unless next_link.exists?

    puts "Opening next results page..."
    browser.goto next_link.href
  end
rescue StandardError => e
  binding.pry
ensure
  product_browser.close
  browser.close

  unless results.empty?
    puts 'Saving reviews to csv file...'
    CSV.open("results.csv", 'wb', write_headers: true, headers: PRODUCT_PARSERS.keys) do |csv|
      results.each { |review| csv << review }
    end
  end
end
