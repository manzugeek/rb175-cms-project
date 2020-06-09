require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require "fileutils"

configure do
  enable :sessions
  set :session_secret, 'super secret'
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  when ".jpeg"
    headers["Content-Type"] = "image/jpeg"
    content
  when ".jpg"
    headers["Content-Type"] = "image/jpg"
    content
  when ".png"
    headers["Content-Type"] = "image/png"
    content
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  unless user_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def invalid_extension?(filename)
  return true unless filename =~ (/.txt$|.md$|.jpg$|.jpeg$|.png$/)
end

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :index
end

get "/new" do
  require_signed_in_user

  erb :new
end

get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit
end

post "/create" do
  require_signed_in_user

  filename = params[:filename].to_s

  if filename.size == 0
    session[:message] = "A name is required."
    status 422
    erb :new
  elsif invalid_extension?(filename)
    session[:message] = "Document type not supported."
    status 422
    erb :new
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, "")
    session[:message] = "#{params[:filename]} has been created."

    redirect "/"
  end
end

post "/:filename" do
  require_signed_in_user

  time = Time.new

  file_path = File.join(data_path, params[:filename])
  file_ext = File.extname(file_path)
  file_name = File.basename(file_path, file_ext)
  
  duplicate_name = "#{file_name}(org_#{time.strftime("%m_%d_%Y")})#{file_ext}"
  dup_file_path = File.join(data_path, duplicate_name)
  
  FileUtils.cp(file_path, dup_file_path)

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.delete(file_path)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end

get "/users/signin" do
  erb :signin
end

get "/users/signup" do
  erb :signup
end

post "/users/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

post "/:filename/duplicate" do
  require_signed_in_user
  
  file_path = File.join(data_path, params[:filename])
  file_ext = File.extname(file_path)
  file_name = File.basename(file_path, file_ext)
  
  duplicate_name = "#{file_name}(dup)#{file_ext}"
  dup_file_path = File.join(data_path, duplicate_name)
  
  file_content = load_file_content(file_path)
  
  File.write(dup_file_path, file_content)
  session[:message] = "#{file_name}#{file_ext} duplicate has been created."
  
  redirect "/"
end

post "/users/signup" do
  username = params[:username]
  password = params[:password]
  hashed_password = BCrypt::Password.create(password)
  
  credentials = load_user_credentials

  if credentials.key?(username)
    session[:message] = "Sorry, that username already exists."
    redirect "users/signup"
  else
    credentials[username] = hashed_password
    credentials_path = File.expand_path("../users.yml", __FILE__)
    File.open(credentials_path, "w") { |file| file.write(credentials.to_yaml) }

    session[:message] = "#{username} was added to the user database."
    redirect "/"
  end
end
