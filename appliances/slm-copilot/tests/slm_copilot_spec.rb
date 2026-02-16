require_relative '../../../lib/community/app_handler'

RSpec.describe 'SLM-Copilot Appliance' do
  before(:all) do
    @app = Community::AppHandler.new
    @app.wait_until_ready(timeout: 600)
  end

  it 'has LocalAI service running' do
    expect(@app.execute('systemctl is-active local-ai').strip).to eq('active')
  end

  it 'has Nginx service running' do
    expect(@app.execute('systemctl is-active nginx').strip).to eq('active')
  end

  it 'serves HTTPS on port 443' do
    result = @app.execute('curl -sk -o /dev/null -w "%{http_code}" https://localhost/')
    expect(result.strip).to eq('401')
  end

  it 'returns 200 on /readyz with auth' do
    password = @app.execute('cat /var/lib/slm-copilot/password').strip
    result = @app.execute(
      "curl -sk -u copilot:#{password} -o /dev/null -w \"%{http_code}\" https://localhost/readyz"
    )
    expect(result.strip).to eq('200')
  end

  it 'lists the devstral-small-2 model' do
    password = @app.execute('cat /var/lib/slm-copilot/password').strip
    result = @app.execute(
      "curl -sk -u copilot:#{password} https://localhost/v1/models"
    )
    parsed = JSON.parse(result)
    model_ids = parsed['data'].map { |m| m['id'] }
    expect(model_ids).to include('devstral-small-2')
  end

  it 'completes a chat request' do
    password = @app.execute('cat /var/lib/slm-copilot/password').strip
    result = @app.execute(
      'curl -sk -u copilot:' + password + ' https://localhost/v1/chat/completions ' \
      '-H "Content-Type: application/json" ' \
      '-d \'{"model":"devstral-small-2","messages":[{"role":"user","content":"Say hello"}],"max_tokens":5}\''
    )
    parsed = JSON.parse(result)
    expect(parsed['choices']).not_to be_empty
    expect(parsed['choices'][0]['message']['content']).not_to be_empty
  end

  it 'has the report file with connection info' do
    result = @app.execute('cat /etc/one-appliance/config')
    expect(result).to include('endpoint')
    expect(result).to include('api_password')
    expect(result).to include('devstral-small-2')
  end
end
