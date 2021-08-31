# encoding: utf-8
require 'sxp'
require 'json'
require 'pp'

class FreshID
  def initialize
    @count = 10000
  end
  def get()
    @count += 1
  end
end

class Compiler

    def initialize()
      @env_trace = {}
      @env_event = {}
      @table = {}
      @fresh = FreshID.new
      @layoutX= {}  # TraceID => [:x, N] | TraceID
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
      case s_exp
        in [:leg, leg_id, plans, events]
          plan_tile_blocks = compile_plans(plans)

          tile_blocks = integrate_events(events, plan_tile_blocks)

          structured_blocks = layout_bloks(tile_blocks)

      else raise "accOunt: Syntax Error\n  leg should be a form like (leg N plans events)\n"
      end
    end

    def compile_plans(plans_sxp)
      # plans ::= [:plans, [:plan, planID, plan_list], ...]
      unless plans_sxp[0].equal?(:plans) then
         raise "AccOunt: syntax error.\n  expect plans but not fed"
      end

      # print("\nplans[1..-1]: #{plans_sxp[1..-1]}\n")
      plans_sxp[1..-1].map { |plan_sxp|
        unless plan_sxp[0].equal?(:plan) then
           raise "Account: syntax error.\n  expected plan, found #{plan_sxp[0]}"
        end
        plan_id = plan_sxp[1]
        traces = plan_sxp[2..-1]
        traces.map { |trace|
          compile_trace(trace)
          # case trace
          #   in [trace_id, [:go, linear_obj], [:get, finish_obj]]
          #     print("trace!! id:#{trace_id}\n")
          #   in [trace_id, :straight, [:get, finish_obj]]
          #     print("trace!! id:#{trace_id}\n")
          # end
        }
      }
    end

    def compile_trace(trace_sxp)
      case trace_sxp
        in [trace_id, move, recognize]
          path = compile_move(move)
          target = compile_recognize(recognize)
          @env_trace[trace_id] = target
        # in [trace_id, :straight, finish_obj_sxp]
        #   path = "直進する"
        #   target = compile_obj(finish_obj_sxp)
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
                  # PP.pp(plans_compiled[current_row])
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
      #   msg = nil
      #   new_plan = nil
      #   call_back = (id) => nil
      #   case action_sxp
      #     in :'as-plan'
      #       msg = "プラン通り"
      #     in [move, [:unconfirmed, obj]]
      #       # TODO 認識できない情報を反映する
      #       msg = compile_obj(move)
      #       _ = compile_obj(obj)
      #       call_back = (id) => 
      #   end
      # end

    ############# Layout ####################

    def get_tile(tile_blocks, id)
      tile_blocks.flatten.find{ |tile|
        # print("get_item\nid: ")
        # print(id)
        # print("\nsearch for: ")
        # print(tile[:id])
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
          # tile が unplanned場合
          # print("\nlast_id: #{last_id}\n")
          # print(tile)
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
          # print(@table[tile[:id]])
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
  res

  # expr2 = C.scan(Ex2)
  # res2 = C.compile(expr2)
  
end
