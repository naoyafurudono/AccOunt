require 'sxp'
require 'pp'

class Top
  def initialize(source)
    @sxp = SXP::Reader::Scheme.read source
  end

  def compile()
    @leg ||= LegC.new(@sxp)
  end

  # For debug
  def leg() @leg end 

  def json()
    compile.json
  end

  def text()
    compile.text
  end
end

# Abstract
class Compiler

  def initialize(sxp)
    raise "ERROR" unless sxp
    @sxp = sxp
  end

  def json()
    "json undef #{self}"
    ""
  end
  # def children()
  #   @children = ir()
  # end

  def error(kind = 'Error', expected = 'IDK', found = 'IDK')
    raise "AccOunt: #{kind}\n  Expected: #{expected}\n  Found: #{found}"
  end

  def id?(obj)
    obj.is_a?(Integer)
  end
end

class LegC < Compiler
  def initialize(sxp)
    super
    case @sxp
    in [:leg, leg_id, plans, events] if id?(leg_id)
      @plans = PlansC.new(plans)
      @events = EventsC.new(events)
      @id = leg_id
    else error('syntax error', '[:leg, leg_id, plans, events]', @sxp)
    end
  end

  # eventのフレームを軸に、プランを対応した構造
  # [{e: [event-frame], p: [trace-frame]}]
  def frame() 
    pf = @plans.frame
    ef = @events.frame

    plan_ids_arr = pf.map{ |p| p[1]}
    ef.map{ |es|
      related_plan_ids = es.map { |e| e[:rel2]}
      plan_framei = plan_ids_arr.index { |pids| (not (pids & related_plan_ids).empty?)}
      {e: es, p: pf[plan_framei]}
    }

  end

  def contents() {p: @plans.contents, e: @events.contents} end

  # frame はconstract_matrixのコメントで書かれた構造
  def number_matrix(frame)
    x, y, next_x = 0, 0, 0
    connectors = []
    matrix = frame.map{ |tiles| 
      executed = false
      x = next_x
      tmp = tiles.map{ |tile|
        tmp = tile.append({x: x, y: y})
        if executed && (not tile_executed?(tile)) then
          next_x = x
          connectors.append({x1: x-1, y1: y, x2:x, y2:y+1})
        end
        x += 1
        executed = (not tile[1].empty?)
        tmp
      }
      y += 1
      tmp
    }
    [matrix, x, y, connectors]
  end

  # Frame = [{e:[{id: --, rel2: --} ...], p: [ID, [ID...]]}...]
  def constract_matrix(frame)
    frame.map{ |h| merge_plan_event(h) }
  end

  def fresh() 
    @fresh ||= 100000
    @fresh += 1 
  end

  # h: {e:[{id: --, rel2: --} ...], p: [ID, [ID...]]}
  def merge_plan_event(h)
    # [[pid, [e...]]...]  それぞれの e rel2 pid
    pairs = h[:p][1].map{ |i| [i, h[:e].filter{ |e| e[:rel2] == i }]}
    # eの列の先頭部分に存在しうる、unplannedなeventたち
    floated_es = h[:e] - pairs.map{ |pair| pair[1]}.flatten
    # 対応するペアを持たないイベントに、プレイスホルダを対応させておく
    # floated_es.map{ |e| [fresh(), [e]] }.concat(pairs)
    floated_es.map{ |e| [nil, [e]] }.concat(pairs)
  end

  def tile_executed?(t)
        not t[1].empty?
  end

  # Tile -> {id: , rel2: }
  def tile_event(t)
    t[1][0]
  end

  def tile_plan(t)
    t[0]
  end

  def tile_place(t)
    t[2]
  end

  def extract_eenv(ev_hash, eenv)
    event = eenv.find {|e| e.id == ev_hash[:id]}
  end

  def extract_penv(p_id, penv)
    penv.values.flatten.find{ |trace| trace.id == p_id }
  end
  
  def json()
    layout = number_matrix(constract_matrix(frame))

    matrix = layout[0]
    x = layout[1]
    y = layout[2]
    connectors = layout[3]

    env = contents()
    penv = env[:p]
    eenv = env[:e]

    PP.pp matrix
    components = matrix.flatten(1).map do |t|
      if tile_plan(t).nil?
        then
         type = "unplanned" 
         event = extract_eenv(tile_event(t), eenv)
         j = event.json
         target = j[:target]
         path =j[:path]
        #  annotation = 
      else
        type = tile_executed?(t) ? "executed" : "planned"
        plan = extract_penv(tile_plan(t), penv)
        j = plan.json
        target = j[:target]
        path =j[:path]
      end
      {x: tile_place(t)[:x], y: tile_place(t)[:y], data: {\
        type: type, target: target, path: path}}
    end
    {xSize: x, ySize: y, components: components, connectors: connectors}
  end

  def text()
    frame = frame()
    contents = contents()
    p_cont = contents[:p]
    e_cont = contents[:e]

    res = "レッグ#{@id}では" 

    res << frame.map{ |h| 
      plan_name, plan_ids = h[:p]
      PP.pp h[:e]
      unplanned_ids, planned_ids = h[:e].partition{|ev| ev[:rel2].nil? }
      PP.pp unplanned_ids
      traces = p_cont[plan_name]
      tmp_msg = ""

      
      unless unplanned_ids.empty?
        tmp_msg << "ここでプランから外れて次のような行動をとった\n  "
        tmp_msg << unplanned_ids.map{ |ev| 
          # PP.pp ev
          # PP.pp unplanned_ids
          ev[:id].to_s.to_s + ". " + e_cont.find{|e| e.id == ev[:id] }.text
        }.join("\n  ") << "\nそこで"
      end

      tmp_msg << plan_name.to_s
      tmp_msg << "として以下を考えた\n  "
      tmp_msg << plan_ids.map{ |trace_id| 
        trace_id.to_s + ". " + traces.find{|t| t.id == trace_id }.text
      }.join("\n  ") << "\n"

      tmp_msg << "このプランのもとで次のように実際の行動をとった\n  "
      tmp_msg << planned_ids.map{ |ev| 
        ev[:id].to_s.to_s + ". " + e_cont.find{|e| e.id == ev[:id] }.text
      }.join("\n  ") << "\n"
    
    }.join("")
  end
end

class PlansC < Compiler
  def initialize(sxp)
    super
    error('syntax error', '[:plans, ...]', @sxp) unless @sxp[0] == :plans
    @id = @sxp[1]
    @plan_arr = @sxp[1..].map { |plan| PlanC.new(plan) }
  end

  def frame() @plan_arr.map{ |p| p.frame } end

  def contents() 
    hash = {}
    @plan_arr.each{ |p| hash[p.id] = p.contents } 
    hash
  end

  # Return plans frame (array of array of plan-id)
  def json()
    tmp = @plan_ir.map {|plan| plan.json()}
    @tiles = @plan_ir.empty? ? {} : @plan_ir[0].tiles.merge(*@plan_ir[1..].map{|ir|ir.tiles})
    tmp
  end

end

class PlanC < Compiler
  def initialize(sxp)
    super
    error() unless @sxp[0] == :plan && @sxp[1].is_a?(Symbol)
    @id = @sxp[1]
    @trace_arr = @sxp[2..].map {|trace| TraceC.new(trace)}
  end

  attr_reader :id

  def frame() [@id, @trace_arr.map{ |t| t.frame}] end

  def contents() @trace_arr end
  # Return plan frame (array)
  def json()
    @trace_arr.map{|trace| 
      tile = trace.json 
      @tiles[trace.id] = trace
      trace.id
    }
  end

  attr_reader :tiles
end

class TraceC < Compiler
  def initialize(sxp)
    super
    case @sxp
      in [trace_id, move, recognize] if id?(trace_id)
        @move = MoveC.new(move)
        raise @sxp unless recognize
        @recognize = RecognizeC.new(recognize)
        @id = trace_id
    end
  end

  def id()
    @id
  end

  def frame() @id end

  # () -> Hash (like JSON)
  def json()
    {\
        :type => "planned"\
      , :target => @recognize.json\
      , :path => @move.json\
    }
  end

  def text()
    @move.text + "。" + @recognize.text + "を確認する"
  end
end

class MoveC < Compiler
  def initialize(sxp)
    super
    case @sxp
      in [:go, obj_sxp]
        @obj = ObjC.new(obj_sxp)
        @tag = :go
      in :straight
        @tag = :straight
    else error('syntax error', "Move", @sxp)
    end
  end

  def json()
    case @tag
    when :go
      @obj.json << "に沿う"
    when :straight
      "直進する"
    end
  end
  def text() json end
end

class RecognizeC < Compiler
  def initialize(sxp)
    super
    case @sxp
      in [:get, obj_sxp]
        @finish = ObjC.new(obj_sxp)
        @tag = :get
      in [:for, n] if n >= 0
        @tag = :for
        @finish = n  # TODO 外から扱いやすいように、構造を定義しなおす
      in :straight
        @tag = :straight
    end    
  end

  def json()
    case @tag
    when :get
      @finish.json
    when :for 
      n.to_s << "進む"
    when :straight
      "まっすぐ"
    end
  end

  def text() json end
end

class ObjC < Compiler
  def initialize(sxp)
    super
    case @sxp
      in [e_sxp, obj_sxp1] if Es.related?(e_sxp)
        # @tag = :e
        @obj = Es.new(@sxp)
      in [g_sxp, obj_sxp1] if Gs.related?(g_sxp)
        # @tag = :g
        @obj = Gs.new(@sxp)
      in [g2_sxp, obj1, obj2] if G2s.related?(g2_sxp)
        # @tag = :g2
        @obj= G2s.new(@sxp)
      in [:plan, n] if id?(n)  # TODO implement
        @tag = :plan
        @obj = Ref.new(n)
      in d_sxp
        # @tag = :d
        @obj = Ds.new(d_sxp)
      # else error('syntax error', 'object', @sxp)
    end
  end

  def json()
    @obj.json
  end
    
  def text()
    @obj.text
  end
end

class EventsC < Compiler
  def initialize(sxp)
    super
    error("Events") unless @sxp[0] == :events
    @event_arr = @sxp[1..].map { |event| EventC.new(event) }
  end

  # [[event.frame]] : event が対応するプランが変わるところで分割した構造
  # 変わり目とは planned -> unplanned の変わり目のこと
  def frame()
    badway = true
    arr_arr_event_frame = []
    arr_event_frame = []
    @event_arr.each do |e| 
      case [badway, e.unplanned?]
      when [false, true]  # planned -> unplnned
        arr_arr_event_frame.append(arr_event_frame)
        arr_event_frame = [e.frame]
        badway = true
      else 
        arr_event_frame.append(e.frame)
        badway = e.unplanned?
      end
    end
    arr_arr_event_frame.append(arr_event_frame)
    arr_arr_event_frame
  end

  def contents() @event_arr end

  # Return event frame (array of plan-id)
  def json()
    @tiles = @ir.map{|e| e.json}
    @event_frame = @tiles.map{|t| t.id }
  end

  attr_reader :tiles

end

class EventC < Compiler
  def initialize(sxp)
    super
    case @sxp
      in [id, action_sxp, recog_sxp, rel2plan_sxp] if id?(id)
        @action = ActionC.new(action_sxp)
        # raise sxp unless recog_sxp
        @recog = RecognizeC.new(recog_sxp)
        @rel2plan = Rel2PlanC.new(rel2plan_sxp)
        @id = id
      end
  end

  def id()
    @id
  end
  def frame() {id: @id, rel2: @rel2plan.rel2 } end

  def unplanned?() @rel2plan.unplanned? end

  def json()
    path, annotation = @action.json
    {\
      :type => @rel2plan.type\
      , :target => @recog.json\
      , :path => path\
      , :annotation => annotation}
  end

  def text()
    @action.text + "。" + @recog.text + "。"
  end
end

class ActionC < Compiler
  def initialize(sxp)
    super
    case @sxp
      in :'as-plan'
        @tag = :'as-plan'
      in [move_sxp, aware_sxp] unless move_sxp.is_a?(Symbol)
        @move = MoveC.new(move_sxp)
        @aware = AwareC.new(aware_sxp)
        @tag = :move
      in move_sxp
        @move = MoveC.new(move_sxp)
        @tag = :move
    end
  end

  def json()
    case @tag
    when :'as-plan'
      return "プラン通り", nil
    when :move
      return @move.json, (@aware ? @aware.json : nil)
    end
  end

  def text()
    case @tag
    when :'as-plan'
      "プラン通り"
    when :move
      @move.text
    end
  end
end

class AwareC < Compiler
  def initialize(sxp)
    super
    case @sxp
    in [:unconfirmed, obj_sxp]
      @obj = ObjC.new(obj_sxp)
      @tag = :unconfirmed
    end
  end

  def json()
    {message: "確認できない", obj: @obj}
  end
end

class Rel2PlanC < Compiler
  def initialize(sxp)
    super
    case @sxp
    in [tag, trace_id, conf] if id?(trace_id) && conf.is_a?(Integer)
      error("runtime error", "0-3", conf) unless 0 <= conf && conf <= 3
      @tag = tag
      @rel2_id = trace_id  # ID で持つべき？対応するオブジェクトを持つべき？ オブジェクトを持つなら、参照はどうやって計算する？
      @conf = conf
      @planned = true
    in :unrelated
      @tag = :unrelated
      @planned = false
    end
  end

  def rel2() @rel2_id end

  def unplanned?() (not @planned) end

  def type()
    case @tag
    when :unrelated
      "unplanned"
    when :related
      "executed"
    when :done
      "executed"
    end
  end
end

# Abstract class
class ObjDescripter < Compiler
  def self.Descripters()
    []
  end

  def self.related?(sxp)
    Descripters().include?(sxp)
  end

  def initialize(sxp)
    super
    @descripter = ""
    @sub_objs = []
  end

  def json
    text()
  end

  def text()
    @sub_objs.map {|obj| obj.text}.join("と") + (@sub_objs.empty? ? "" : "の") + @descripter.to_s
  end
end

class Ds < ObjDescripter
  def self.Descripters()
    [:テラス, :尾根, :沢, :土がけ, :採石場, :土塁・堤防\
      , :きれつ, :小さなきれつ, :こぶ, :小さなこぶ, :鞍部\
      , :凹地, :小凹地, :穴, :凹凸地, :アリ塚, :岩がけ, :がけの間の通過部分\
      , :湖, :池・沼 , :湧水点, :貯水槽・水桶, :開けた土地, :半ば開けた土地\
      , :独立樹, :切り株・木の根, :道路, :道, :道・小道・小径, :パイプライン\
      , :建物の通過できる部分, :階段, :川, :岩\
      , :目的地] 
  end

  def initialize(sxp)
    super
    @descripter = sxp
  end

  def text()
    @sxp.to_s
  end
end

class Es < ObjDescripter
  def self.Descripters()
    [:低い, :浅い, :深い, :植物の茂っている, :開けた, :岩の・岩状の, :湿地状の, :砂地状の, :針葉樹の, :広葉樹の, :倒れた・壊れた]
  end

  def initialize(e_sxp)
    super
    case e_sxp
    in [descripter, sub_obj]
      @descripter = descripter
      @sub_objs = [ObjC.new(sub_obj)]
    end
  end
end

class Gs < ObjDescripter
  def self.Descripters()
    [:側, :ふち, :部分, :内側の角, :外側の角, :突端, :曲がり,\
      :終わり, :上の部分, :下の部分, :上, :下, :根本, :傾斜の変わり目, :線]
  end

  def initialize(sxp)
    super
    case sxp
    in [descripter, sub_obj]
      @descripter = descripter
      @sub_objs = [ObjC.new(sub_obj)]
    end
  end
end

class G2s < ObjDescripter
  def self.Descripters()
    [:交点, :分岐, :間, :変わり目]
  end

  def initialize(sxp)
    super
    case sxp
    in [desc, obj1, obj2]
      @descripter = desc
      @sub_objs = [obj1, obj2].map{|sxp| ObjC.new(sxp)}
    end
  end

  # def json()
  #   @sub_objs[0].json << @descripter.to_s << @sub_objs[1].json
  # end
end

class Ref < ObjDescripter
  def initialize(n)
    super
    @descripter = "プラン#{n}で記述したところ"
  end
end


###### JSON ######

class Tile
  def initialize(hash, id)
    @json_hash = hash
    @id = id 
  end
  
  def type()
    @json_hash[:type].intern
  end

  attr_reader :id
end

class Row
  def initialize(tile_arr)
     @tile_arr = tile_arr; @prep = []
     @connectors = []
  end

  def add2prepend(tile)
    @prep.append(tile)
  end

  def get()
    @tile_arr = @prep.concat(@tile_arr)
    connect!(@prep.append(@tile_arr[0]))
    @prep = []
    print @connectors, "\n"
    @tile_arr
  end

  def connect!(tiles)
    return unless tiles.length >= 2
    (@tile_arr.length - 2).times{ |i|
      e = i + 1
      ti = @tile_arr[i]
      te = @tile_arr[e]
      @connectors << {x1: ti.x, y1: ti.y, x2: te.x, y2: te.y}
    }
  end

  def update(tile)
    puts @tile_arr.find{|base_tile| base_tile.id == tile.id}
  end
end

# グラフの表現方法について
# すべてのtileは直後のtileを知っていて
# すべてのrowは
class Matrix
  # @rowsとevent_tilesから、このmatrixのトポロジーを定める
  def integrate_events(event_tiles)
    pos = 0
    planed = true

    event_tiles.each do |tile|
      case tile.type
      when :executed
        planed = true
      when :unplanned
        if planed
          pos += 1
          planed = false
        end
        @rows[pos].add2prepend(tile)
      end
      @rows.each {|r| r.update(tile)}
    end

    return @rows.map{|r| r.get}
  end
end

require './compiler'

# def t  
#   Top.new(Ex1)
# end

def l
  t = Top.new(Ex1)
  t.compile
  t.leg
end