%%%---------------------------------------------------------------------------------------
%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2009 Max Lapshin
%%% @doc        RTMP functions, that support recording
%%% @reference  See <a href="http://erlyvideo.org/" target="_top">http://erlyvideo.org</a> for more information
%%% @end
%%%
%%% This file is part of erlyvideo.
%%% 
%%% erlyvideo is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% erlyvideo is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with erlyvideo.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%---------------------------------------------------------------------------------------
-module(apps_recording).
-author('Max Lapshin <max@maxidoors.ru>').
-include("../log.hrl").
-include_lib("rtmp/include/rtmp.hrl").
-include_lib("erlmedia/include/video_frame.hrl").

-export([publish/2]).
-export(['FCPublish'/2, 'FCUnpublish'/2]).
-export(['DVRSetStreamInfo'/2]).


%%-------------------------------------------------------------------------
%% @private
%%-------------------------------------------------------------------------

'FCPublish'(State, #rtmp_funcall{args = [null, Name]} = _AMF) -> 
  Socket = rtmp_session:get(State, socket),
  SessionId = rtmp_session:get(State, session_id),
  ?D({"FCpublish", Name}),
  Args = {object, [
    {level, <<"status">>}, 
    {code, <<"NetStream.Publish.Start">>},
    {description, <<"FCPublish to ", Name/binary>>},
    {clientid, SessionId}
  ]},
  % rtmp_session:reply(State, AMF#rtmp_funcall{args = [null, 0]}),
  rtmp_socket:invoke(Socket, 0, 'onFCPublish', [Args]),
  State.

'FCUnpublish'(State, #rtmp_funcall{args = [null, FullName]} = _AMF) ->
  Host = rtmp_session:get(State, host),
  {RawName, _Args1} = http_uri2:parse_path_query(FullName),
  Name = string:join( [Part || Part <- ems:str_split(RawName, "/"), Part =/= ".."], "/"),
  case media_provider:find(Host, Name) of
    {ok, Media} -> ems_media:set_source(Media, undefined);
    _ -> ?D({error,stream_is_absent,Host,Name})
  end,
  % ems_event:stream_source_lost(Host,Name,SessionId),
  % media_provider:remove(Host, Name),
  State.

'DVRSetStreamInfo'(State, #rtmp_funcall{args = [null, {object, Info}]} = _AMF) ->
  ?D({'DVRSetStreamInfo', Info}),
  State.
  
  
real_publish(State, FullName, Type, StreamId) ->
  Host = rtmp_session:get(State, host),
  Socket = rtmp_session:get(State, socket),
  SessionId = rtmp_session:get(State, session_id),
  Addr = rtmp_session:get(State, addr),
  UserId = rtmp_session:get(State, user_id),
  SessionId = rtmp_session:get(State, session_id),

  {RawName, Args1} = http_uri2:parse_path_query(FullName),
  Name = string:join( [Part || Part <- ems:str_split(RawName, "/"), Part =/= ".."], "/"),
  Options1 = extract_publish_args(Args1),
  % Options = lists:ukeymerge(1, Options1, [{source_timeout,shutdown},{type,Type}]),
  Options = lists:ukeymerge(1, Options1, [{type,Type},{registrator,true}]),
  
  ems_log:access(Host, "PUBLISH ~p ~s ~p ~p ~s", [Type, Addr, UserId, SessionId, Name]),
  {ok, Recorder} = media_provider:create(Host, Name, Options),
  ?D({"publish",Type,Options,Recorder}),
  Ref = erlang:monitor(process, Recorder),
  
  rtmp_lib:notify_publish_start(Socket, StreamId, SessionId, Name),
  
  rtmp_session:set_stream(rtmp_stream:construct([{pid,Recorder},{recording_ref,Ref},{stream_id,StreamId},{started, true}, {recording, true}, {name, Name}]), State).
  
extract_publish_args([]) -> [];
extract_publish_args({"record", "true"}) -> {type, record};
extract_publish_args({"source_timeout", "infinity"}) -> {source_timeout, infinity};
extract_publish_args({"source_timeout", "shutdown"}) -> {source_timeout, shutdown};
extract_publish_args({"source_timeout", Timeout}) -> {source_timeout, list_to_integer(Timeout)};
extract_publish_args({"timeshift", Timeshift}) -> {timeshift, list_to_integer(Timeshift)};
extract_publish_args({Key, Value}) -> {Key, Value};
extract_publish_args(List) -> [extract_publish_args(Arg) || Arg <- List].

publish(State, #rtmp_funcall{args = [null,Name, <<"record">>], stream_id = StreamId} = _AMF) -> 
  real_publish(State, Name, record, StreamId);

publish(State, #rtmp_funcall{args = [null,Name,<<"append">>], stream_id = StreamId} = _AMF) -> 
  real_publish(State, Name, append, StreamId);

publish(State, #rtmp_funcall{args = [null,Name,<<"LIVE">>], stream_id = StreamId} = _AMF) ->
  real_publish(State, Name, live, StreamId);

publish(State, #rtmp_funcall{args = [null,Name,<<"live">>], stream_id = StreamId} = _AMF) -> 
  real_publish(State, Name, live, StreamId);

publish(State, #rtmp_funcall{args = [null, false]} = AMF) ->
  apps_streaming:stop(State, AMF);

publish(State, #rtmp_funcall{args = [null, null]} = AMF) ->
  apps_streaming:stop(State, AMF);

publish(State, #rtmp_funcall{args = [null, <<"null">>]} = AMF) ->
  apps_streaming:stop(State, AMF);
  
publish(State, #rtmp_funcall{args = [null,Name], stream_id = StreamId} = _AMF) -> 
  real_publish(State, Name, live, StreamId).

