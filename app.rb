require 'sinatra'
# require 'sinatra/reloader'  # for dev: サーバの再起動をせずにプログラムの変更内容を反映できる
require './compileR'

# configure do
#     mime_type :accOunt "application/x.accOunt"
# end

class App < Sinatra::Base
  get '/' do
      File.read(File.join('public', 'index.html'))
  end

  post '/compile/accOunt/text', provides: 'application/x.accOunt' do
      content_type :'text/plain'
      begin
        t = Top.new(request.body.read)
        t.compile
        t.text
      rescue => exception
        "AccOunt: Failed to generate explanation"
      end
  end

  post '/compile/accOunt/legs', provides: 'application/x.accOunt' do
      T = Top.new(request.body.read)
      T.compile
      # sample = {
      #     xSize: 6,
      #     ySize: 2,
      #     components: [
      #         {x: 0, y:0, data: {"type": "executed", "target": "川の終わり", "path": "川に沿う"}},
      #         {x: 1, y:0, data: {"type": "executed", "target": "岩", "path": "尾根線に沿う"}},
      #         {x: 2, y:0, data: {"type": "executed", "target": "道", "path": "直進"}},
      #         {x: 3, y:0, data: {"type": "planned", "target": "半ば開けた土地と開けた土地の変わり目", "path": "道に沿う", "annotation": "確認できない"}},
      #         {x: 4, y:0, data: {"type": "planned", "target": "目的地", "path": "直進"}},
      #         {x: 3, y:1, data: {"type": "unplanned", "target": "道と道の分岐", "path": "道に沿う"}},
      #         {x: 4, y:1, data: {"type": "executed", "target": "道の終わり", "path": "道に沿う"}},
      #         {x: 5, y:1, data: {"type": "executed", "target": "目的地", "path": "沢底に沿う"}},
      #     ],
      #     connectors: [
      #         {x1: 2, y1: 0, x2: 3, y2: 1}
      #     ]
      # }
      # res = sample
      content_type :json
      T.json.to_json
  end

  run! if app_file == $0
end

