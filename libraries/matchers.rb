if defined?(ChefSpec)
  def serialize_locking_resource(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:locking_resource,
                                            :serialize, resource_name)
  end

  def serialize_process_locking_resource(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:locking_resource,
                                            :serialize_process, resource_name)
  end
end
