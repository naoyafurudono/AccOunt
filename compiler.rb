# encoding: utf-8
require 'sxp'
require 'json'
require 'pp'

class Compiler
    class FreshID
      def initialize
        @count = 10000
      end
      def get()
        @count += 1
      end
    end

    def initialize()
      @plan_compiled = nil
      @event_integrated = nil
      @env_trace = {}
      @table = {}
      @fresh = FreshID.new
      @layoutX= {}  # TraceID => [:x, N] | TraceID
      @cache = false
      @natural = ""
    end
    def table()
      @table
    end
    def env()
      @env_trace
    end

    def deref_layout(id)
      print(@layoutX)
      print("\n")
      print("id: #{id}\n")
      case @layoutX[id]
        in [:x, n]
          print("choose [:x, #{n}]")
          n
        in nil
          raise "AccOunt: internal error.\n  deref_layout"
        in new_id if new_id.integer?
          print("rec; #{new_id}\n")
          deref_layout(new_id) + 1
      else raise "AccOunt: internal error.\n  deref_layout"
      end
    end
    ############## Primitives ##############

    Ds = [:テラス, :尾根, :沢, :土がけ, :採石場, :土塁・堤防\
      , :きれつ, :小さなきれつ, :こぶ, :小さなこぶ, :鞍部\
      , :凹地, :小凹地, :穴, :凹凸地, :アリ塚, :岩がけ, :がけの間の通過部分\
      , :湖, :池・沼 , :湧水点, :貯水槽・水桶, :開けた土地, :半ば開けた土地\
      , :独立樹, :切り株・木の根, :道路, :道, :道・小道・小径, :パイプライン\
      , :建物の通過できる部分, :階段, :川, :岩\
      , :目的地]
    Es = [:低い, :浅い, :深い, :植物の茂っている, :開けた, :岩の・岩状の, :湿地状の, :砂地状の, :針葉樹の, :広葉樹の, :倒れた・壊れた]
    Gs = [:側, :ふち, :部分, :内側の角, :外側の角, :突端, :曲がり,\
       :終わり, :上の部分, :下の部分, :上, :下, :根本, :傾斜の変わり目, :線]
    G2s = [:交点, :分岐, :間, :変わり目]

    #########################################

    # AccOunt -> S-exp
    def scan(accout)
        SXP::Reader::Scheme.read accout
    end

    ################################ Compiler ####################################

    # S-exp -> Hash
    def compile(s_exp)
      initialize()
      case s_exp
        in [:leg, leg_id, plans, events]
          @plan_compiled = compile_plans(plans)
          puts("debug: compile_plans res")
          PP.pp(@plan_compiled)

          @event_integrated = integrate_events(events, @plan_compiled)

          structured_blocks = layout_bloks(@event_integrated)
          @cache = structured_blocks

      else raise "accOunt: Syntax Error\n  leg should be a form like (leg N plans events)\n"
      end
    end

    def compile_plans(plans_sxp)
      unless plans_sxp[0].equal?(:plans) then
         raise "AccOunt: syntax error.\n  expect plans but not fed"
      end

      plans_sxp[1..-1].map { |plan_sxp|
        unless plan_sxp[0].equal?(:plan) then
           raise "Account: syntax error.\n  expected plan, found #{plan_sxp[0]}"
        end
        plan_id = plan_sxp[1]
        traces = plan_sxp[2..-1]
        traces.map { |trace|
          compile_trace(trace)
        }
      }
    end

    def compile_trace(trace_sxp)
      case trace_sxp
        in [trace_id, move, recognize]
          path = compile_move(move)
          target = compile_recognize(recognize)
          @env_trace[trace_id] = target
        # TODO in ... 軌跡ID

          data = {id: trace_id ,:data => {"target"=> target, path: path, "type"=>"planned"}}
          @table[trace_id] = data
      else raise "AccOunt: syntax error.\n  Expect: trace, but found #{trace}"
      end
      return data
    end

    def compile_move(move_sxp)
      case move_sxp
        in [:go, linear_obj_sxp]
          compile_obj(linear_obj_sxp)
        in :straight
          "直進する"
      else raise "AccOunt: syntax error.\n Expect 移動, found #{move_sxp}"
      end
    end

    def compile_recognize(recognize_sxp)
      case recognize_sxp
        in [:get,obj]
          compile_obj(obj) << ""
        in [:for, n] if n >= 0
          n.to_s << "メートル進む"
        in :finish
          "終える"
      end
    end

    def compile_obj(obj_sxp)
      def compile_obj_e(e)
        e.to_s
      end

      def compile_obj_g(g)
        case g
          in g_sym if Gs.include?(g_sym)
            g_sym.to_s
          in ["側", direction]
            direction.to_s + "側"
          in "の終わり"
            g.to_s
        else
          "undef: compile_obj_g"
        end
      end

      def compile_obj_g2(g2)
        g2.to_s
      end

      case obj_sxp
        # D
        in obj if Ds.include?(obj)
          obj.to_s
        # (E obj)
        in [e, obj_sxp1] if Es.include?(e)
          compile_obj_e(e) << compile_obj(obj_sxp1)
        in [g, obj_sxp1] if Gs.include?(g) 
          compile_obj(obj_sxp1) << "の" << compile_obj_g(g)
        in [g2, obj_sxp1, obj_sxp2] if G2s.include?(g2)
          (compile_obj(obj_sxp1) << "と" << compile_obj(obj_sxp2) << "の" << compile_obj_g2(g2))
        in [:plan, n] if n.integer?
          @env_trace[n] || (raise "AccOunt: runtime error.\n  plan #{n} is undefined")
      end
    end

    ######### integrate events ########
    def to_move(action)
      case action
        in :'as-plan'
          :straight
        in [:go, _]
          action
        in [move, _]
          move
        in move
          move
      end
    end

    def integrate_events(events_sxp, plans_compiled)
      raise "AccOunt: syntax error.\n  expected events, found #{events_sxp[0]}" unless events_sxp[0].equal?(:events)

      current_row = 0
      current_trace = 0
      status = true  # プラン通り?
      unplanned_tiles = []

      event_sxps = events_sxp[1..-1]
      event_sxps.each { |event|
        case event
          in [event_id, action_sxp, recognize_sxp, rel2plan_sxp] if event_id.integer?
            case rel2plan_sxp
              in [:done, trace_id, conf] if trace_id.integer? && conf.integer?
                @table[trace_id][:data]["type"] = "executed"
                current_trace = trace_id

                if (not status)
                  status = true
                  plans_compiled[current_row].prepend(unplanned_tiles).flatten!
                  unplanned_tiles = []
                end
              in :unrelated
                # このeventをフレームに追加する
                # 1. IDを与える
                # 2. traceを生成して、compile_traceに食わせる ~~> tableの更新とフレームデータの生成ができる
                # 3. 生成したフレームをしかるべきところに追加する
                id = @fresh.get()
                trace = [id, to_move(action_sxp), recognize_sxp]
                trace_compiled = compile_trace(trace)
                @table[id][:data]["type"] = "unplanned"
                # plans_compiled[current_row].prepend trace_compiled
                PP.pp(trace_compiled)
                unplanned_tiles.append trace_compiled
                PP.pp(unplanned_tiles)
                current_row += 1 if status
                status = false

                # レイアウトのための情報
                @layoutX[id] = current_trace
                current_trace = id
            end
            case action_sxp
              in [_, [:unconfirmed, [:plan, n]]]
                @table[n][:data]["annotation"] = "確認できない"
            else nil
            end
        end
      }
      plans_compiled
    end

    ############# Layout ####################

    def get_tile(tile_blocks, id)
      tile_blocks.flatten.find{ |tile|
        tile[:id].eql?(id)} || (raise "AccOunt: internal error. get_tile")
    end

    def layout_bloks(tile_blocks)
      y_size = 0
      x_size = 0

      connectors = []
      # Invaliants
      #  - x_size = その時点までで最大のx方向の大きさ
      #  - y_size = 使用済みの列の直後のインデックス
      last_id = nil
      for block in tile_blocks do
        x = 0
        y = y_size
        for tile in block do
          if tile[:data].key?("type") && tile[:data]["type"].eql?("unplanned")
            x = deref_layout(tile[:id])

            # Draw connector
            prev_tile = get_tile(tile_blocks, last_id)
            connectors.append({x1: prev_tile[:x], y1: prev_tile[:y], x2: x, y2: y})
          end
          tile[:x] = x
          tile[:y] = y
          @layoutX[tile[:id]] = [:x, x]
          x += 1
          last_id = tile[:id] if ["executed", "unplanned"].include?(@table[tile[:id]][:data]["type"])
        end
        x_size = [x_size, x + 1].max
        y_size += 1  # この時点では未使用の列
      end

      {xSize: x_size, ySize: y_size,\
       components: tile_blocks.flatten ,\
       connectors: connectors}
    end

    ################ end Layout ################

  def makeNatural(expr)
    @cache = compile(expr) unless @cache
    res = ""

    case expr
      in [:leg, leg_id, plans, events]
        natural(plans, events, res)
    else raise "AccOunt: syntax error. makeNatural"
    end
  end

  def natural(plans, events, res)
    plan_arr = plans[1..-1]
    PP.pp(plans)
    PP.pp(plan_arr)
    plan = plan_arr[0]
    plan2natural(plan)

  end

  def plan2natural(plan)
    raise "AccOunt internal" unless plan[0].equal?(:plan)
    plan_name = plan[1]
    trace_arr = plan[2..-1]
    plan_name.to_s << "としては以下のものを考えた:\n  "<< trace_arr.map{ |trace| trace2natural(trace)}.join(sep="\n  ")
  end
  def trace2natural(trace)
    case trace
      in [id, move, finish]
        "(#{id}) " << move2natural(move) << finish2natural(finish) << "まで行く"
    end
  end

  def move2natural(move)
    case move
      in [:go, obj]
        compile_obj(obj) << "に沿って"
      in :straight
        "直進で"
    end
  end

  def finish2natural(finish)
    case finish
      in [:get, obj]
        compile_obj(obj)
      in :finish
        "終わり"
    end
  end
end
##################### end Compiler ###########

#### For test ####

C = Compiler.new

Ex1 = "
(leg 1
(plans
  (plan 初期プラン
    [1
      (go 道)
      (get (分岐 道 川))]
    [2
      (go 川)
      (get (終わり 川))]
    [3
      (go (線 尾根))
      (get 岩)]
    [4    ;; hogehoge
      straight
      (get 道)]
    [5
      (go 道)
      (get (変わり目 半ば開けた土地 開けた土地))]
    [6
      straight
      (get 目的地)]
    )
  (plan 新しいプラン
    [8
      (go 道)
      (get (終わり 道))]
    [9
      (go (線 沢))
      (get 目的地)]
    ))
(events
    [1
      straight 
      (get (plan 3))
      (done 3 3)]
    [2
      as-plan
      (get 道)
      (done 4 3)]
    [3
      ((go 道)
       (unconfirmed (plan 5)))
      (get (分岐 道 道))
      unrelated]
    [5
     as-plan
     (get (plan 8))
     (done 8 3)]
    [6
      (go (線 沢))
      (get 目的地)
      (done 9 3)]
      )
)"

Ex2 = "(leg 1
(plans
  (plan 初期プラン
    [1
      (go 道)
      (get (分岐 道 川))]
    [2
      (go 川)
      (get (終わり 川))]
    [3
      (go (線 尾根))
      (get 岩)]
    [4    ;; hogehoge
      straight
      (get 道)]
    [5
      (go 道)
      (get (変わり目 半ば開けた土地 開けた土地))]
    [6
      straight
      (get 目的地)]
    )
  (plan 新しいプラン
    [8
      (go 道)
      (get (終わり 道))]
    [9
      (go (線 沢))
      (get 目的地)]
    ))
(events
    [1
      straight 
      (get (plan 3))
      (done 3 3)]
    [2
      as-plan
      (get 道)
      (done 4 3)]
    [3
      ((go 道)
       (unconfirmed (plan 5)))
      (get (分岐 道 道))
      unrelated]
    [10
       (go (線 沢))
       (get (分岐 (線 沢) 川))
       unrelated]
    [5
     as-plan
     (get (plan 8))
     (done 8 3)]
    [6
      (go (線 沢))
      (get 目的地)
      (done 9 3)]
      )
)"

def test()
  s_exp = C.scan(Ex1)
  res = C.compile(s_exp)
  print("DEBUG: compiler output:\n")
  PP.pp(res)
  PP.pp C.makeNatural(s_exp)
  # res

  # expr2 = C.scan(Ex2)
  # res2 = C.compile(expr2)
  
end
