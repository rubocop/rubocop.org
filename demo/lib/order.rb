class Order
  def total(items)
    discount = 0.1
    items.sum(&:price)
  end
end
