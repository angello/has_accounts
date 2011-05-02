class Booking < ActiveRecord::Base
  # Validation
  validates_presence_of :debit_account, :credit_account, :title, :amount, :value_date
  validates_time :value_date

  # Account
  belongs_to :debit_account, :foreign_key => 'debit_account_id', :class_name => "Account"
  belongs_to :credit_account, :foreign_key => 'credit_account_id', :class_name => "Account"

  def direct_account
    return nil unless reference
    
    return reference.direct_account if reference.respond_to? :direct_account
  end
  
  def contra_account(account = nil)
    # Derive from direct_account if available
    account ||= direct_account

    return unless account

    if debit_account == account
      return credit_account
    elsif credit_account == account
      return debit_account
    else
      return nil
    end
  end
  
  # Scoping
  default_scope order('value_date, id')

  scope :by_value_date, lambda {|value_date| where("date(value_date) = ?", value_date) }
  scope :by_value_period, lambda {|from, to| where("date(value_date) BETWEEN :from AND :to", :from => from, :to => to) }
  
  scope :by_account, lambda {|account_id|
    { :conditions => ["debit_account_id = :account_id OR credit_account_id = :account_id", {:account_id => account_id}] }
  } do
    # Returns array of all booking titles.
    def titles
      find(:all, :group => :title).map{|booking| booking.title}
    end
    
    # Statistics per booking title.
    #
    # The statistics are an array of hashes with keys title, count, sum, average.
    def statistics
      find(:all, :select => "title, count(*) AS count, sum(amount) AS sum, avg(amount) AS avg", :group => :title).map{|stat| stat.attributes}
    end
  end

  scope :by_text, lambda {|value|
    text   = '%' + value + '%'
    
    amount = value.delete("'").to_f
    if amount == 0.0
      amount = nil unless value.match(/^[0.]*$/)
    end
    
    date   = nil
    begin
      date = Date.parse(value)
    rescue ArgumentError
    end
    
    where("title LIKE :text OR comments = :text OR amount = :amount OR value_date = :value_date", :text => text, :amount => amount, :value_date => date)
  }
  
  # Returns array of all years we have bookings for
  def self.fiscal_years
    with_exclusive_scope do
      select("DISTINCT year(value_date) AS year").all.map{|booking| booking.year}
    end
  end

  # Standard methods
  def to_s(format = :default)
    case format
    when :short
      "%s: %s / %s CHF %s" % [
        value_date ? value_date : '?',
        credit_account ? credit_account.code : '?',
        debit_account ? debit_account.code : '?',
        amount ? "%0.2f" % amount : '?',
      ]
    else
      "%s: %s an %s CHF %s, %s (%s)" % [
        value_date ? value_date : '?',
        credit_account ? "#{credit_account.title} (#{credit_account.code})" : '?',
        debit_account ? "#{debit_account.title} (#{debit_account.code})" : '?',
        amount ? "%0.2f" % amount : '?',
        title.present? ? title : '?',
        comments.present? ? comments : '?'
      ]
    end
  end

  # Helpers
  def accounted_amount(account)
    if credit_account == account
      balance = -(amount)
    elsif debit_account == account
      balance = amount
    else
      return BigDecimal.new('0')
    end

    if account.is_asset_account?
      return -(balance)
    else
      return balance
    end
  end

  def amount_as_string
    '%0.2f' % amount
  end
  
  def amount_as_string=(value)
    self.amount = value
  end
  
  def rounded_amount
    if amount.nil?
    	return 0
    else
    	return (amount * 20).round / 20.0
    end
  end

  # Templates
  def booking_template_id
    nil
  end
  
  def booking_template_id=(value)
  end
  
  # Helpers
  def split(amount, params = {})
    # Clone
    new_booking = self.clone

    # Set amount
    new_booking[:amount] = amount
    self.amount -= amount
    
    # Update attributes
    params.each{|key, value|
      new_booking[key] = value
    }
    
    [self, new_booking]
  end
  
  # Reference
  belongs_to :reference, :polymorphic => true
  after_save :notify_references

  # Safety net for form assignments
  def reference_type=(value)
    write_attribute(:reference_type, value) unless value.blank?
  end

  scope :by_reference, lambda {|value|
    where(:reference_id => value.id, :reference_type => value.class.base_class)
  } do
    # TODO duplicated in Invoice
    def direct_balance(direct_account)
      balance = 0.0

      for booking in all
        balance += booking.accounted_amount(direct_account)
      end

      balance
    end
  end
  
  private
  def notify_references
    return unless reference and reference.respond_to?(:booking_saved)
    reference.booking_saved(self)
  end
end
