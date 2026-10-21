class CpfValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    digits = value.to_s
    valid = digits.match?(/\A[0-9]{11}\z/) && digits.chars.uniq.length > 1
    if valid
      numbers = digits.chars.map(&:to_i)
      valid = [9, 10].all? do |length|
        sum = numbers.first(length).each_with_index.sum { |number, index| number * (length + 1 - index) }
        check = (sum * 10) % 11
        check = 0 if check == 10
        numbers[length] == check
      end
    end
    record.errors.add(attribute, :invalid) unless valid
  end
end
