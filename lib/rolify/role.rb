module Rolify
  @@role_cname = "Role"
  @@user_cname = "User"
  @@dynamic_shortcuts = false
  
  def self.configure
    yield self if block_given?
  end

  def self.role_cname
    @@role_cname.constantize
  end

  def self.role_cname=(role_cname)
    @@role_cname = role_cname.camelize
  end

  def self.user_cname
    @@user_cname.constantize
  end

  def self.user_cname=(user_cname)
    @@user_cname = user_cname.camelize
  end

  def self.dynamic_shortcuts
    @@dynamic_shortcuts || false
  end

  def self.dynamic_shortcuts=(is_dynamic)
    @@dynamic_shortcuts = is_dynamic
    self.user_cname.load_dynamic_methods if is_dynamic
  end

  module Roles

    def has_role(role_name, resource = nil)
      role = Rolify.role_cname.find_or_create_by_name_and_resource_type_and_resource_id(role_name, 
                                                                                        (resource.is_a?(Class) ? resource.to_s : resource.class.name if resource), 
                                                                                        (resource.id if resource && !resource.is_a?(Class)))
      if !roles.include?(role)
        self.class.define_dynamic_method(role_name, resource) if Rolify.dynamic_shortcuts
        self.role_ids |= [role.id]
      end
    end
    alias_method :grant, :has_role
  
    def has_role?(role_name, resource = nil)
      query, values = build_query(role_name, resource)
      self.roles.where(query, *values).size > 0
    end

    def has_all_roles?(*args)
      conditions, values, count = sql_conditions(args, true)
      self.roles.where([ conditions.join(' OR '), *values ]).where(count.join(') AND (')).size > 0
    end

    def has_any_role?(*args)
      conditions, values = sql_conditions(args)
      self.roles.where([ conditions.join(' OR '), *values ]).size > 0
    end
  
    def has_no_role(role_name, resource = nil)
      role = self.roles.where(:name => role_name)
      role = role.where(:resource_type => (resource.is_a?(Class) ? resource.to_s : resource.class.name)) if resource
      role = role.where(:resource_id => resource.id) if resource && !resource.is_a?(Class)
      self.roles.delete(role) if role
    end
    alias_method :revoke, :has_no_role
  
    def roles_name
      self.roles.select(:name).map { |r| r.name }
    end

    def method_missing(method, *args, &block)
      if method.to_s.match(/^is_(\w+)_of[?]$/) || method.to_s.match(/^is_(\w+)[?]$/)
        if Rolify.role_cname.where(:name => $1).count > 0
          resource = args.first
          self.class.define_dynamic_method $1, resource
          return has_role?("#{$1}", resource)
        end
      end unless !Rolify.dynamic_shortcuts
      super
    end
 
    private
 
    def sql_conditions(args, count = false)
      conditions = []
      count_conditions = [] if count
      values = []
      args.each do |arg|
        if arg.is_a? Hash
          a, v = build_query(arg[:name], arg[:resource])
        elsif arg.is_a? String
          a, v = build_query(arg)
        else
          raise ArgumentError, "Invalid argument type: only hash or string allowed"
        end
        conditions << a
        count_conditions << self.roles.where(a, *v).select("COUNT(id)").to_sql + " > 0" if count
        values += v
      end
      count ? [ conditions, values, count_conditions ] : [ conditions, values ]
    end

    def build_query(role, resource = nil)
      return [ "name = ?", [ role ] ] if resource == :any
      query = "((name = ?) AND (resource_type IS NULL) AND (resource_id IS NULL))"
      values = [ role ]
      if resource
        query.insert(0, "(")
        query += " OR ((name = ?) AND (resource_type = ?) AND (resource_id IS NULL))" 
        values << role << (resource.is_a?(Class) ? resource.to_s : resource.class.name)
        if !resource.is_a? Class
          query += " OR ((name = ?) AND (resource_type = ?) AND (resource_id = ?))" 
          values << role << resource.class.name << resource.id
        end
        query += ")"
      end
      [ query, values ]
    end

  end

  module Dynamic
 
    def load_dynamic_methods
      Rolify.role_cname.all.each do |r|
        define_dynamic_method(r.name, r.resource)
      end
    end

    def define_dynamic_method(role_name, resource)
      class_eval do 
        define_method("is_#{role_name}?".to_sym) do
        has_role?("#{role_name}")
        end if !method_defined?("is_#{role_name}?".to_sym)
  
        define_method("is_#{role_name}_of?".to_sym) do |arg|
          has_role?("#{role_name}", arg)
        end if !method_defined?("is_#{role_name}_of?".to_sym) && resource
      end
    end    
  end
end