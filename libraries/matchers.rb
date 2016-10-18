if defined?(ChefSpec)
  def serialize_locking_resource(name)
    ChefSpec::Matchers::ResourceMatcher.new(:locking_resource, :serialize, name)
  end
end
