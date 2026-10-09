class Greeter
  def sayHello(name)
    if name.nil?
      name = "stranger"
    end
    return "Hello, #{name}!"
  end
end
