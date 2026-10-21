class ApplicationController < ActionController::API
  before_action :prevent_caching
  attr_reader :current_user, :current_session

  rescue_from ActiveRecord::RecordInvalid do |exception|
    # Details only contain field names/codes, never rejected personal values.
    render_error("validation_error", "Dados inválidos.", status: :unprocessable_entity,
                 details: exception.record.errors.attribute_names)
  end
  rescue_from ActiveRecord::RecordNotFound do
    render_error("not_found", "Recurso não encontrado.", status: :not_found)
  end
  rescue_from ActiveRecord::RecordNotUnique do
    render_error("validation_error", "Dados inválidos.", status: :unprocessable_entity)
  end
  rescue_from ActionController::ParameterMissing do
    render_error("invalid_request", "Requisição inválida.", status: :bad_request)
  end

  private

  def authenticate!
    scheme, token = request.headers["Authorization"].to_s.split(" ", 2)
    @current_session = Auth::SessionService.authenticate(token) if scheme == "Bearer" && token.present?
    @current_user = @current_session&.user
    render_error("unauthorized", "Autenticação inválida ou expirada.", status: :unauthorized) unless @current_user
  end

  def render_error(code, message, status:, details: nil)
    error = { code: code, message: message }
    error[:details] = details if details
    render json: { error: error }, status: status
  end

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end
end
