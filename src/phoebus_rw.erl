%%%-------------------------------------------------------------------
%%% @author Arun Suresh <>
%%% @copyright (C) 2010, Arun Suresh
%%% @doc
%%%
%%% @end
%%% Created :  4 Oct 2010 by Arun Suresh <>
%%%-------------------------------------------------------------------
-module(phoebus_rw).
-include("phoebus.hrl").

%% API
-export([init/1, partition_input/1, read_vertices_start/1, destroy/1]).

%%%===================================================================
%%% API
%%%===================================================================
init(URI) ->
  case URI of
    [$h, $d, $f, $s, $:, $/, $/ | AbsPath] -> 
      {ok, check_dir(URI, [{uri, URI}, {abs_path, AbsPath}, {type, dets}])};
    [$f, $i, $l, $e, $:, $/, $/ | AbsPath] -> 
      {ok, check_dir(URI, [{uri, URI}, {abs_path, AbsPath}, {type, file}])}
  end.

partition_input(State) ->
  case proplists:get_value(is_dir, State) of
    true ->
      {ok, Files} = file:list_dir(proplists:get_value(abs_path, State)),
      Base = proplists:get_value(uri, State),
      {ok, [Base ++ F || F <- Files], State};
    _ ->
      {error, State}
  end.
             
read_vertices_start(State) ->
  case proplists:get_value(is_dir, State) of
    false ->
      start_reading(proplists:get_value(type, State), 
                    proplists:get_value(abs_path, State), State);
    _ ->
      {error, State}
  end.  

destroy(_) ->
  void.
 
%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

%%%===================================================================
%%% Internal functions
%%%===================================================================
check_dir(URI, Conf) ->
  case lists:last(URI) of
    $/ -> [{is_dir, true} | Conf];
    _ -> [{is_dir, false} | Conf]
  end.
      
start_reading(file, File, State) ->
  MyPid = self(),
  RPid = spawn(fun() -> reader_loop({init, File}, MyPid, {State, []}) end),
  {ok, RPid, State}.


reader_loop({init, File}, Pid, State) ->
  {ok, FD} = file:open(File, [raw, {read_ahead, 16384}]),
  reader_loop(FD, Pid, State);
reader_loop(FD, Pid, {State, Buffer}) ->
  case file:read_line(FD) of
    {ok, Line} ->
      case convert_to_rec(Line) of
        nil -> reader_loop(FD, Pid, {State, Buffer});
        V -> 
          case length(Buffer) > 100 of
            true ->
              gen_fsm:send_event(Pid, {vertices, [V|Buffer], self(), State}),
              reader_loop(FD, Pid, {State, []});
            _ ->
              reader_loop(FD, Pid, {State, [V|Buffer]})
          end
      end;
    eof ->
      gen_fsm:send_event(Pid, {vertices_done, Buffer, self(), State}),
      file:close(FD)
  end.
      
  
%% {Vid, VName, VVal, VState, [{EVal, VName}]
%% vname \t vval \t [eval \t tvname \t].. \n
convert_to_rec(Line) ->
  convert_to_rec(Line, #vertex{}, [], [], vname).

convert_to_rec([$\n | _], #vertex{vertex_id = nil}, _, _, _) -> nil;
convert_to_rec([$\n | _], V, EList, _, _) ->
  {V#vertex.vertex_name, V#vertex.vertex_value, EList};
convert_to_rec([$\t | Rest], V, EList, Buffer, vname) ->
  VName = lists:reverse(Buffer),
  VId = erlang:phash2(VName, 4294967296),
  convert_to_rec(Rest, V#vertex{vertex_id = VId, 
                                vertex_name = VName}, EList, [], vval);
convert_to_rec([$\t | Rest], V, EList, Buffer, vval) ->
  convert_to_rec(Rest, V#vertex{vertex_value = lists:reverse(Buffer)}, 
                 EList, [], eval);
convert_to_rec([$\t | Rest], V, EList, Buffer, eval) ->
  convert_to_rec(Rest, V, EList, [], {tvname, lists:reverse(Buffer)});
convert_to_rec([$\t | Rest], V, EList, Buffer, {tvname, EVal}) ->
  VName = lists:reverse(Buffer),
  convert_to_rec(Rest, V, [{EVal, VName}|EList], [], eval);
convert_to_rec([X | Rest], V, EList, Buffer, Token) ->
  convert_to_rec(Rest, V, EList, [X|Buffer], Token).
