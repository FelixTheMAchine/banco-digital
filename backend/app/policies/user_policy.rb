class UserPolicy
  def initialize(user, resource)
    @user = user
    @resource = resource
  end

  def manage?
    @user&.active? && @resource.id == @user.id
  end
end
