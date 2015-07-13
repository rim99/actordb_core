-module(actordb_test).
-export([batch_write/0]).
-include_lib("eunit/include/eunit.hrl").
-include_lib("actordb_sqlproc.hrl").
% -include_lib("actordb.hrl").
% misc internal tests
% general tests are in actordb/test/dist_test.erl and run with detest


batch_write() ->
	Actor = butil:tobin(butil:epochsec()),
	{sql_error,A,B} = actordb_sqlproc:write({Actor,type1},[create],"insert into tab values (1,'a',2,3);",actordb_actor),
	?AINF("Create actor with error: {sql_error,~p,~p}",[A,B]),
	% Actor now exists with schema and no data (insert failed)
	Pid = distreg:whereis({Actor,type1}),
	% For every write create ref to match against (id and ref).
	W = [{{self(),make_ref()},#write{sql = "insert into tab values (1,'a',2);"}},
	{{self(),make_ref()},#write{sql = "insert into tab values (2,'b',3);"}},
	{{self(),make_ref()},#write{sql = "insert into tab values (3,'c',4,5);"}},
	{{self(),make_ref()},#write{sql = "insert into tab values (4,'d',5);"}},
	{{self(),make_ref()},#write{sql = "insert into tab values (5,'aa',1);"}}],
	Pid ! {batch,W},
	ok = recbatch(W,1),

	R = [{{self(),make_ref()}, #read{sql = "select * from tab where id=1;"}},
	{{self(),make_ref()}, #read{sql = "select * from tab where id=2;"}},
	{{self(),make_ref()}, #read{sql = "select * from tab where xid=3;"}},
	{{self(),make_ref()}, #read{sql = "select * from tab where id=4;"}},
	{{self(),make_ref()}, #read{sql = "select * from tab where id=5;"}}],
	Pid ! {batch,R},
	ok = recbatch(R,1),

	ok.

recbatch([{{_,Ref},R}|T],Id) ->
	receive
		{Ref,{sql_error,A,B}} when Id == 3 ->
			?AINF("Correctly received error for invalid sql in batch: ~p,~p",[A,B]),
			recbatch(T,Id+1);
		{Ref,{ok,{changes,Id,1}}} when element(1,R) == write ->
			?AINF("Received correct write response for id=~p",[Id]),
			recbatch(T,Id+1);
		{Ref,{ok,[{columns,{<<"id">>,<<"txt">>,<<"i">>}},{rows,[{Id,_,_}]}]}} when element(1,R) == read ->
			?AINF("Received correct read response for id=~p",[Id]),
			recbatch(T,Id+1)
		% X when element(1,R) == read ->
		% 	?AERR("REC read: ~p",[X]),
		% 	recbatch(T,Id+1)
	after 1000 ->
		timeout
	end;
recbatch([],_) ->
	ok.
