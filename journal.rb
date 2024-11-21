require 'json'
require 'date'
require 'io/console'
require 'ruby/openai'
require 'erb'

data_folder = File.join(__dir__, 'data')

# Load or create data JSON
data_json_path = File.join(data_folder, 'data.json')
data_json = File.exist?(data_json_path) ? JSON.parse(File.read(data_json_path)) : {}

client = OpenAI::Client.new(access_token: data_json['openai']['apiKey'])

# Load previous questions and answers
qa_file = File.join(data_folder, 'previousQuestionsAndAnswers.json')
questions_and_answers = File.exist?(qa_file) ? JSON.parse(File.read(qa_file)) : {}

# Get last 5 dates with answers
last_five_dates = []
if questions_and_answers['dateMap']
  past_dates = questions_and_answers['dateMap'].reverse
  past_dates.each do |date|
    if questions_and_answers['answers'] &&
        questions_and_answers['answers'][date] &&
        !questions_and_answers['answers'][date].empty?
      last_five_dates << date
      break if last_five_dates.length == 5
    end
  end
end

# Format previous Q&As
today = Date.today.iso8601
qa_text = ""

last_five_dates.each do |date|
  next unless questions_and_answers['answers'] && questions_and_answers['answers'][date]

  days_ago = (Date.parse(today) - Date.parse(date)).to_i
  day_of_week = Date.parse(date).strftime('%A')

  qa_text << case days_ago
    when 0
      "Today, #{day_of_week} (#{date}), #{data_json['name']}'s Q&As were:\n"
    when 1
      "Yesterday, #{day_of_week} (#{date}), #{data_json['name']}'s Q&As were:\n"
    when 2
      "#{day_of_week} just gone (#{date}), #{data_json['name']}'s Q&As were:\n"
    else
      "Last #{day_of_week} (#{date}), #{data_json['name']}'s Q&As were:\n"
  end

  questions_and_answers['answers'][date].each_with_index do |qa, i|
    qa_text += "Q#{i + 1}: #{qa['question']}\n"
    qa_text += "A#{i + 1}: #{qa['answer']}\n"
  end
  qa_text += "\n"
end

todolist = `reminders show "To do"`

template = File.read('prompt.erb')
prompt = ERB.new(template).result_with_hash(questions_and_answers: qa_text, todolist: todolist)
messages = [{ role: 'user', content: prompt }]

# Print messages
puts messages.map { |m| m[:content] }.join("\n\n")

# Get questions from GPT
questions = []
escape_counter = 0

while questions.length != 3 && escape_counter < 10
  questions.clear

  if escape_counter == 0
    puts "\nThinking of some questions to ask you, please wait."
  else
    puts "Getting some different questions"
  end

  begin
    start_time = Time.now
    response = client.chat(
      parameters: {
        model: 'gpt-4o',
        messages: messages
      }
    )
    output = response.dig('choices', 0, 'message', 'content').to_s.strip.gsub(/[\r\n]+/, "\n").gsub(/[\t ]+/, ' ')

    duration = (Time.now - start_time).to_i
    puts "Response: #{duration}s"

    output.split("\n").each do |line|
      line = line.gsub(/^[0-9]+[.) :]/, '').strip
      questions << line unless line.empty?
    end
  rescue => e
    puts "Error: #{e.message}"
    exit
  end

  escape_counter += 1
end

# Add general question
questions << "Anything else you want to mention?"

# Get answers from user
answers = []
questions.each_with_index do |question, i|
  puts "\n#{i + 1}: #{question}"
  print "> "
  answer = gets.chomp
  answers << answer
end

# Save answers
date = Date.today.iso8601
questions_and_answers['answers'] ||= {}
questions_and_answers['dateMap'] ||= []
questions_and_answers['dateMap'] << date unless questions_and_answers['dateMap'].include?(date)
questions_and_answers['answers'][date] = []

questions.each_with_index do |question, i|
  next if answers[i].strip.empty?
  questions_and_answers['answers'][date] << {
    'question' => question,
    'answer' => answers[i]
  }
end

File.write(qa_file, JSON.pretty_generate(questions_and_answers))
puts "\nThank you for your time, have a good day."
