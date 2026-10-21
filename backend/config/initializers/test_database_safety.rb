# Não permitir que um terminal com DATABASE_URL de desenvolvimento limpe dados reais.
if Rails.env.test?
  database = ActiveRecord::Base.connection_db_config.database.to_s
  raise "O banco de testes deve ter nome terminado em _test" unless database.end_with?("_test")
end
