class Account < ActiveRecord::Base
  belongs_to :holder, :polymorphic => true
  
  has_many :credit_bookings, :class_name => "Booking", :foreign_key => "credit_account_id"
  has_many :debit_bookings, :class_name => "Booking", :foreign_key => "debit_account_id"
  
  def bookings
    Booking.by_account(id)
  end
  
  # Standard methods
  def to_s(value_range = Date.today, format = :default)
    case format
    when :short
      "#{code}: CHF #{sprintf('%0.2f', saldo(value_range).currency_round)}"
    else
      "#{title} (#{code}): CHF #{sprintf('%0.2f', saldo(value_range).currency_round)}"
    end
  end

  def self.overview(value_range = Date.today, format = :default)
    Account.all.map{|a| a.to_s(value_range, format)}
  end
  
  def turnover(selector = Date.today, inclusive = true)
    if selector.is_a? Range or selector.is_a? Array
      if selector.first.is_a? Booking
        equality = "=" if inclusive
        if selector.first.value_date == selector.last.value_date
          condition = ["value_date = :value_date AND id >#{equality} :first_id AND id <#{equality} :last_id", {
            :value_date => selector.first.value_date,
            :first_id => selector.first.id,
            :last_id => selector.last.id
          }]
        else
          condition = ["(value_date > :first_value_date AND value_date < :latest_value_date) OR (value_date = :first_value_date AND id >#{equality} :first_id) OR (value_date = :latest_value_date AND id <#{equality} :last_id)", {
            :first_value_date => selector.first.value_date,
            :latest_value_date => selector.last.value_date,
            :first_id => selector.first.id,
            :last_id => selector.last.id
          }]
        end
      elsif
        # TODO support inclusive param
        condition = {:value_date => selector}
      end
    else
      if selector.is_a? Booking
        equality = "=" if inclusive
        condition = ["(value_date < :value_date) OR (value_date = :value_date AND id <#{equality} :id)", {:value_date => selector.value_date, :id => selector.id}]
      else
        equality = "=" if inclusive
        condition = ["value_date <#{equality} ?", selector]
      end
    end

    credit_amount = credit_bookings.sum(:amount, :conditions => condition)
    debit_amount = debit_bookings.sum(:amount, :conditions => condition)
    
    [credit_amount || 0.0, debit_amount || 0.0]
  end
  
  def saldo(selector = Date.today, inclusive = true)
    credit_amount, debit_amount = turnover(selector, inclusive)

    return credit_amount - debit_amount
  end
end
