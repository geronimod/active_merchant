require 'test_helper'

class CyberpacTest < Test::Unit::TestCase
  def setup
    @gateway = CyberpacGateway.new :secret_key => 'h2u282kMks01923kmqpo', 
                                   :merchant_code => 201920191

    @credit_card = credit_card
    @amount = 1235
    
    @options = { 
      :order_id => 29292929,
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  def test_signature
    assert_equal 'a4eac839e072f4549177ff51fdb2408362270362', 
                 @gateway.send(:signature, :purchase, @amount, @credit_card, @options[:order_id])
  end
  
  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of ActiveMerchant::Billing::Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal '', response.authorization
    assert response.test?
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?
  end

  private
  
  # Place raw successful response from gateway here
  def successful_purchase_response
  end
  
  # Place raw failed response from gateway here
  def failed_purchase_response
  end
end
