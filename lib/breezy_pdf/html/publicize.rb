# frozen_string_literal: true

module BreezyPDF::HTML
  # Replace assets with uploaded URL's
  class Publicize
    def initialize(base_url, html_fragment)
      @base_url      = base_url
      @html_fragment = html_fragment
      @log_queue     = []
      @upload_ids    = []
      @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def public_fragment
      @public_fragment ||= parsed_document.tap do
        publicize!
        BreezyPDF.logger.info("[BreezyPDF] Replaced assets in #{timing} seconds")
      end.to_html
    end

    def upload_ids
      public_fragment

      @upload_ids
    end

    def timing
      @timing ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
    end

    private

    def publicize!
      BreezyPDF.asset_selectors.each do |selector|
        parsed_document.css(selector).each do |asset_element|
          replace_asset_elements_matched_paths(asset_element)
        end
      end

      @log_queue.each { |msg| BreezyPDF.logger.info(msg) }

      thread_pool.shutdown
      thread_pool.wait_for_termination
    end

    def parsed_document
      @parsed_document ||= Nokogiri::HTML(@html_fragment)
    end

    def replace_asset_elements_matched_paths(asset_element)
      BreezyPDF.asset_path_matchers.each do |attr, matcher|
        attr_value = asset_element[attr.to_s]

        next unless attr_value && attr_value.match?(matcher)

        @log_queue << %([BreezyPDF] Replacing element #{asset_element.name}[#{attr}="#{asset_element[attr]}"])
        replace_asset_element_attr(asset_element, attr.to_s)
      end
    end

    def replace_asset_element_attr(asset_element, attr)
      thread_pool.post do
        asset_element[attr] = BreezyPDF.asset_cache.fetch(asset_element[attr], expires_in: 601_200) do
          asset = BreezyPDF::Resources::Asset.new(@base_url, asset_element[attr])

          upload = BreezyPDF::Uploads::Base.new(
            asset.filename, asset.content_type, asset.file_path
          )
          @upload_ids.push(upload.id)

          upload.public_url
        end
      end
    end

    def thread_pool
      @thread_pool ||= Concurrent::FixedThreadPool.new(BreezyPDF.threads.to_i)
    end
  end
end
