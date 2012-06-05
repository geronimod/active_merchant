# encoding: utf-8
require File.dirname(__FILE__) + '/cyberpac_response'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CyberpacGateway < Gateway
      require 'digest/sha1'
      
      # TODO: implement simple post request method    
      # REDIRECT_TEST_URL = 'https://sis-t.sermepa.es:25443/sis/realizarPago'
      # REDIRECT_LIVE_URL = 'https://sis.sermepa.es/sis/realizarPago'

      # XML post request method
      DIRECT_TEST_URL = 'https://sis-t.sermepa.es:25443/sis/operaciones'
      DIRECT_LIVE_URL = 'https://sis.sermepa.es/sis/operaciones'

      CURRENCY_CODES = { 
        "AUD"=> '036',
        "CAD"=> '124',
        "CZK"=> '203',
        "DKK"=> '208',
        "HKD"=> '344',
        "ICK"=> '352',
        "JPY"=> '392',
        "NOK"=> '578',
        "SGD"=> '702',
        "SEK"=> '752',
        "CHF"=> '756',
        "GBP"=> '826',
        "USD"=> '840',
        "EUR"=> '978'
      }

      TRANSACTIONS = {
        :purchase                           => '0',
        :authorization                      => '1',
        :capture                            => '2',
        :refund                             => '3',
        :payment_reference                  => '4',
        :recurring                          => '5',
        :successive                         => '6',
        :authentication                     => '7',
        :confirm_authentication             => '8',
        :void                               => '9',
        :deferred_authorization             => 'O',
        :capture_deferred_authorization     => 'P',
        :void_deferred_authorization        => 'Q',
        :recurring_deferred_authorization   => 'R',
        :successive_deferred_authorization  => 'S'
      }

      self.money_format = :cents
      self.default_currency = CURRENCY_CODES['EUR']
      self.supported_countries = ['ES']
      self.supported_cardtypes = [:visa, :master]
      self.homepage_url = 'http://empresa.lacaixa.es/comercios/cyberpac_es.html'
      self.display_name = 'Cyberpac'

      def initialize(options = {})
        requires!(options, :merchant_code, :secret_key)
        @options = options
        @options[:merchant_name] ||= 'Merchant Name'
        super
      end  
      
      def authorize(money, creditcard, options = {})
        requires! options, :order_id
        commit :authorization, build_authorization_request(money, creditcard, options), options
      end
      
      def purchase(money, creditcard, options = {})
        requires! options, :order_id
        commit :purchase, build_purchase_request(money, creditcard, options), options
      end                       
    
      def capture(money, authorization, options = {})
        commit :capture, build_capture_request(money, creditcard, options), options
      end
    
      private
        def build_authorization_request(money, creditcard, options = {})
          build_common_request :authorization, money, creditcard, options
        end

        def build_purchase_request(money, creditcard, options = {})
          build_common_request :purchase, money, creditcard, options
        end

        def build_capture_request(money, creditcard, options = {})
          build_common_request :capture, money, creditcard, options
        end

        def build_common_request(transaction, money, creditcard, options = {})
          xml = Builder::XmlMarkup.new :indent => 2
          xml.instruct!

          xml.tag! 'DATOSENTRADA' do
            xml.tag! 'DS_VERSION', 1.0
            add_terminal      xml, options
            add_merchant_data xml, transaction, money, creditcard, options
            add_invoice       xml, transaction, money, options
            add_creditcard    xml, creditcard, options
          end
          
          xml.target!          
        end

        # TODO: implement recurring payments case TRANSACTIONS[:recurring]
        def signature(transaction, amount, creditcard, order_id, options = {})
          currency = options[:currency] || self.class.default_currency
          transaction_code = TRANSACTIONS[transaction]

          # NOTE: the order is important, affects the result digest
          ary = [ amount, order_id, @options[:merchant_code], currency, 
                  creditcard.number, creditcard.verification_value, transaction_code, 
                  @options[:secret_key] 
                ].compact
          
          Digest::SHA1.hexdigest(ary.map(&:to_s).join)
        end

        def add_terminal(xml, options)
          xml.tag! 'DS_MERCHANT_TERMINAL', options[:terminal] || @options[:terminal] || 1
        end

        def add_merchant_data(xml, transaction, money, creditcard, options)
          # xml.tag! 'DS_MERCHANT_MERCHANTURL', '' only if is specified in online merchant interface
          xml.tag! 'DS_MERCHANT_MERCHANTDATA', options[:merchant_data]
          xml.tag! 'DS_MERCHANT_MERCHANTNAME', options[:merchant_name] || @options[:merchant_name]
          xml.tag! 'DS_MERCHANT_MERCHANTSIGNATURE', signature(transaction, money, creditcard, options[:order_id])
          xml.tag! 'DS_MERCHANT_MERCHANTCODE', @options[:merchant_code]
        end

        def add_customer_data(post, options)
        end

        def add_address(post, creditcard, options)      
        end

        def add_invoice(xml, transaction, money, options)
          xml.tag! 'DS_MERCHANT_TRANSACTIONTYPE', TRANSACTIONS[transaction]
          xml.tag! 'DS_MERCHANT_AMOUNT',          money
          xml.tag! 'DS_MERCHANT_CURRENCY',        options[:currency] || self.class.default_currency
          xml.tag! 'DS_MERCHANT_ORDER',           options[:order_id]
        end
        
        def add_creditcard(xml, creditcard, options)
          xml.tag! 'DS_MERCHANT_PAN',        creditcard.number
          xml.tag! 'DS_MERCHANT_EXPIRYDATE', format(creditcard.year, :two_digits) + format(creditcard.month, :two_digits)
          xml.tag! 'DS_MERCHANT_CVV2',       creditcard.verification_value
        end

        def service_url
          test? ? DIRECT_TEST_URL : DIRECT_LIVE_URL
        end

        def commit(action, request, options)
          headers = {
            'Content-Length' => "#{request.size}",
            'User-Agent'     => "Active Merchant - http://activemerchant.org",
            'Content-Type'   => "application/x-www-form-urlencoded"
          }
          p request
          response = parse action, ssl_post(service_url, post_data(:entrada => request), headers)
          CyberpacResponse.new success_from(response), 
                               message_from(response), 
                               response,
                               :authorization => authorization_from(response),
                               :test => test?
        end

        def parse(action, xml)
          p xml
          parse_element({ :action => action }, REXML::Document.new(xml))
        end

        def parse_element(raw, node)
          node.attributes.each do |k, v|
            raw["#{node.name.underscore}_#{k.underscore}".to_sym] = v
          end
          
          if node.has_elements?
            if node.name == 'RECIBIDO'
              raw[:recibido] = node.children.to_s
            else
              raw[node.name.underscore.to_sym] = true unless node.name.blank?
              node.elements.each { |e| parse_element(raw, e) }
            end
          else
            raw[node.name.underscore.to_sym] = node.text unless node.text.nil?
          end
          
          raw            
        end

        def authorization_from(response)
          response[:ds_authorisation_code].try :strip       
        end

        def success_from(response)
          operation_success?(response) && response_code_succeed?(response)
        end

        # see CyberpacResponse for more details
        def response_code_succeed?(response)
          CyberpacResponse.response_code_succeed? response_code_from(response)
        end

        def response_code_from(response)
          response[:ds_response].to_i
        end

        def operation_code_from(response)
          response[:codigo]
        end

        # 0: correct operation, SISCode: incorrect
        def operation_success?(response)
          operation_code_from(response) == '0'
        end

        def message_from(response)
          if success_from(response)
            'SUCCESS'
          elsif operation_success?(response)
            'REFUSED'
          else
            response[:codigo]
          end
        end
        
        def post_data(parameters = {})
          parameters.map { |k,v| "#{k}=#{CGI.escape(v)}" }.join '&'
        end
    end
  end
end

