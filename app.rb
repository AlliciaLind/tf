require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'sinatra/reloader'
require 'date'
require 'time'

enable :sessions

helpers do
    def get_weekday_from_date(year, month, day)
        date = Date.new(year.to_i, month.to_i, day.to_i)
        return date.strftime('%A')
    end

    def get_month_name(month)
        return Date::MONTHNAMES[month]
    end

    def get_todays_date()
        d = DateTime.now
        day_today = d.strftime("%d").to_i
        month_number_today = d.strftime("%m").to_i
        month_name_today = Date::MONTHNAMES[d.strftime("%m").to_i]
        year_today = d.strftime("%Y").to_i
        
        date = [].append(day_today, month_number_today, month_name_today, year_today)
        puts date
        return date
    end

    def get_calendar(year, month)
        days = Date.new(year, month, -1).day
        first_day = Date.new(year, month, 1)
        puts first_day
        weekday = first_day.cwday
        month_information = [year, Date::MONTHNAMES[month], days, weekday]
        puts "--------"
        puts month_information
        return month_information
    end

    def counter(start_number)
        return start_number += 1
    end
end

def open_db(path)
    db = SQLite3::Database.new('db/workout.db')
    db.results_as_hash = true
    return db
end

get('/') do 
    slim :start, layout: false
end

get('/login') do 
    slim :login, layout: false
end

post('/login') do
    email = params[:email]
    password = params[:password]

    db = open_db("db/workout.db")
    result = db.execute("SELECT * FROM users WHERE email = ?", email).first

    if result.nil?
        puts "User not found"
        redirect('/login')
    else
        pwdigest = result['pwdigest']
        id = result['id']

        if BCrypt::Password.new(pwdigest) == password
            session[:id] = id
            session[:user] = result['name']
            session[:user_email] = email
            
            redirect('/overview')
        else
            puts "Wrong password"
        end
    end
end

get('/register') do
    slim :register, layout: false
end

def image_to_binary(image_path)
    File.open(image_path, 'rb') { |file| file.read }
end

post('/users/new') do 
    firstname = params[:firstname]
    lastname = params[:lastname]
    email = params[:email]
    password = params[:password]
    password_confirm = params[:password_confirm]
    #pfp = params[:pfp]
    name = firstname.strip.capitalize + " " + lastname.strip.capitalize
    puts "--------------------------"
    puts name, email, password, password_confirm

    db = open_db("db/workout.db")
    email_taken = []
    email_taken = db.execute("SELECT COUNT (email) AS email_count FROM users WHERE email = ?", email)
    puts "before if"
    puts email_taken.first['email_count']

    if email_taken.first['email_count'] > 0
        puts "Email already in use"
    elsif password == password_confirm
        puts "inside main"
        password_digest = BCrypt::Password.create(password)
        db.execute("INSERT INTO users (name, email, pwdigest) VALUES (?, ?, ?)", name, email, password_digest,)
    else
        puts "Passwords don't match"
    end
    redirect('/login')
end

get('/logout') do
    session.clear
    redirect('/')
end

get('/overview') do
    todays_date = get_todays_date()
    todays_date_str = "#{todays_date[3]}-#{todays_date[1]}-#{todays_date[0]}"
    puts "DATE"
    p todays_date_str

    #For week:
    today = Date.today
    week_start = today - (today.wday - 1) % 7
    week_end = week_start + 6
    week_start_str = week_start.strftime("%Y-%-m-%-d")
    week_end_str = week_end.strftime("%Y-%-m-%-d")
    puts week_start, week_end

    db = open_db("db/workout.db")

    todays_workouts = db.execute("SELECT w.* FROM workouts w
    JOIN workouts_schedules ws ON w.id = ws.workout_id
    JOIN schedules s ON ws.schedule_id = s.id
    WHERE s.date = ? AND s.user_id = ?", [todays_date_str, session[:id]])

    weeks_workouts = db.execute("SELECT w.* FROM workouts w
    JOIN workouts_schedules ws ON w.id = ws.workout_id
    JOIN schedules s ON ws.schedule_id = s.id
    WHERE s.date BETWEEN ? AND ? AND s.user_id = ?", [week_start_str, week_end_str, session[:id]])

    slim(:overview, locals: { todays_workouts: todays_workouts, weeks_workouts: weeks_workouts })
end

get('/myworkouts') do 
    db = open_db("db/workout.db")
    workouts = db.execute("SELECT * FROM workouts WHERE user_id = ?", session[:id])

    slim(:"/workouts/my_workouts", locals: { workouts: workouts })
end

get('/create_new_workout') do 
    slim(:"/workouts/new_workout")
end

post('/workout/new') do 
    title = params[:title]
    description = params[:description]
    exercises = params[:exercise]
    sets = params[:sets]
    reps = params[:reps]

    exercise_tot = []
    i = 0
    while i < exercises.length()
        exercise_group = []
        exercise_group.append(exercises[i])
        exercise_group.append(sets[i])
        exercise_group.append(reps[i])
        exercise_tot.append(exercise_group)
        i += 1
    end

    db = open_db("db/workout.db")
    db.execute("INSERT INTO workouts (user_id, title, description) VALUES (?, ?, ?)", session[:id], title, description)
    workout_id = db.last_insert_row_id

    exercise_tot.each do |exercise|
        db.execute("INSERT INTO exercises (exercise_name, sets, reps, workout_id) VALUES (?, ?, ?, ?)", exercise[0], exercise[1], exercise[2], workout_id)
    end
    
    redirect('/myworkouts')
end

get('/myworkouts/:id') do
    workout_id = params[:id].to_i
    db = open_db("db/workout.db")
    workout = db.execute("SELECT * FROM workouts WHERE id = ?", workout_id).first
    exercises = db.execute("SELECT * FROM exercises WHERE workout_id = ?", workout_id)

    slim(:"/workouts/show_workout", locals: { workout: workout, exercises: exercises })
end

post('/myworkouts/:id/delete') do
    workout_id = params[:id].to_i
    db = open_db("db/workout.db")
    db.execute("DELETE FROM workouts WHERE id = ?", workout_id)
    db.execute("DELETE FROM exercises WHERE workout_id = ?", workout_id)

    redirect('/myworkouts')
end

get('/myworkouts/:id/edit') do
    workout_id = params[:id].to_i
    db = open_db("db/workout.db")
    workout_info = db.execute("SELECT * FROM workouts WHERE id = ?", workout_id).first
    exercises = db.execute("SELECT * FROM exercises WHERE workout_id = ?", workout_id)

    slim(:"/workouts/edit_workout", locals: { workout: workout_info, exercises: exercises })
end

post('/myworkouts/:id/update') do
    id = params[:id].to_i
    title = params[:title]
    description = params[:description]
    exercises = params[:exercise]
    sets = params[:sets]
    reps = params[:reps]

    exercise_tot = []
    i = 0
    while i < exercises.length()
        exercise_group = []
        exercise_group.append(exercises[i])
        exercise_group.append(sets[i])
        exercise_group.append(reps[i])
        exercise_tot.append(exercise_group)
        i += 1
    end

    db = open_db("db/workout.db")
    db.execute("UPDATE workouts SET title = ?, description = ? WHERE id = ?", title, description, id)

    exercise_ids = db.execute("SELECT id FROM exercises WHERE workout_id = ?", id)

    i = 0
    exercise_tot.each do |exercise|
        exercise_id = exercise_ids[i]["id"]
        db.execute("UPDATE exercises SET exercise_name = ?, sets = ?, reps = ? WHERE id = ?", exercise[0], exercise[1], exercise[2], exercise_id)
        i += 1
    end
    
    redirect('/myworkouts')
end

get('/date/:year/:month/:day') do
    year = params[:year]
    month = params[:month]
    day = params[:day]
    date = year + "-" + month + "-" + day
    puts "DATE"
    puts date

    db = open_db("db/workout.db")
    workouts = db.execute("SELECT w.* FROM workouts w
    JOIN workouts_schedules ws ON w.id = ws.workout_id
    JOIN schedules s ON ws.schedule_id = s.id
    WHERE s.date = ? AND s.user_id = ?", [date, session[:id]])

    slim(:"date/show_date", locals: { year: year, month: month, day: day, workouts: workouts })
end

get('/date/add/:year/:month/:day') do
    year = params[:year]
    month = params[:month]
    day = params[:day]
    date = "#{year}-#{month}-#{day}"

    db = open_db("db/workout.db")
    workouts = db.execute("SELECT * FROM workouts WHERE user_id = ?", session[:id])

    slim(:"date/add_date", locals: { year: year, month: month, day: day, workouts: workouts })
end

post('/date/new/:year/:month/:day/:workout_id') do
    year = params[:year]
    month = params[:month]
    day = params[:day]
    workout_id = params[:workout_id]
    date = "#{year}-#{month}-#{day}"
    puts "POST DATE"
    puts date
    puts workout_id

    db = open_db("db/workout.db")
    db.execute("INSERT INTO schedules (user_id, date) VALUES (?, ?) ON CONFLICT (date) DO NOTHING", session[:id], date)

    puts "inserted date"

    schedule_id = db.execute("SELECT id FROM schedules WHERE date = ?", date).first["id"]

    puts "Aquired schedule_id"
    puts schedule_id

    db.execute("INSERT INTO workouts_schedules (workout_id, schedule_id) VALUES (?, ?)", workout_id, schedule_id)


    redirect("/date/#{year}/#{month}/#{day}")
end