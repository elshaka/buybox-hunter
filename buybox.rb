require 'watir'
require 'csv'
require 'pry'

PRODUCT_PARSERS = {
  asin: ->(product) { product.data_asin },
  url: ->(product) { product.a(class: 'a-link-normal').href }
}

url = ARGV[0]
raise ArgumentError.new 'No URL provided' unless url


timestamp = Time.now.strftime('%Y%m%d%H%M%S')
csv_filename = "#{timestamp}.csv"

puts 'Starting web browser...'
browser = Watir::Browser.new :chrome, headless: true
puts 'Opening search results...'
browser.goto url

hunted = []
begin
  1.times do
    next_button = browser.a(class: 's-pagination-next')
    next_button.wait_until(&:exists?)

    next_link = next_button.href

    products = browser.div(class: 's-result-list').children.select { |r| !r.data_asin.empty? }

    products.each do |product_html|
      puts "Checking product #{product_html.data_asin}..."

      hunted << PRODUCT_PARSERS.each_with_object({}) do |(field, parser), product|
        product[field] = parser.call(product_html)
      end
    end

  end
rescue StandardError => e
  warn "An error ocurred while parsing the page #{browser.url}"
  warn "\t#{e.message}"
ensure
  unless hunted.empty?
    puts 'Saving reviews to csv file...'
    CSV.open(csv_filename, 'wb', write_headers: true, headers: PRODUCT_PARSERS.keys) do |csv|
      hunted.each { |review| csv << review }
    end
  end
end
