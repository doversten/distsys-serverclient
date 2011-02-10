%% - Server module
%% - The server module creates a parallel registered process by spawning a process which 
%% evaluates initialize(). 
%% The function initialize() does the following: 
%%      1/ It makes the current process as a system process in order to trap exit.
%%      2/ It creates a process evaluating the store_loop() function.
%%      4/ It executes the server_loop() function.

-module(server).

-export([start/0]).


%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start() -> 
    register(transaction_server, spawn(fun() ->
					       process_flag(trap_exit, true),
					       Val= (catch initialize()),
					       io:format("Server terminated with:~p~n",[Val])
				       end)).

initialize() ->
    process_flag(trap_exit, true),
    Initialvals = [{a,0},{b,0},{c,0},{d,0}], %% All variables are set to 0
    ServerPid = self(),
    StorePid = spawn_link(fun() -> store_loop(ServerPid,Initialvals) end),
    server_loop([],StorePid).
%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% - The server maintains a list of all connected clients and a store holding
%% the values of the global variable a, b, c and d 
server_loop(ClientList,StorePid) ->
    receive
	{login, MM, Client} -> 
	    MM ! {ok, self()},
	    io:format("New client has joined the server:~p.~n", [Client]),
	    StorePid ! {print, self()},
	    server_loop(add_client({Client,[]},ClientList),StorePid);
	{close, Client} -> 
	    io:format("Client~p has left the server.~n", [Client]),
	    StorePid ! {print, self()},
	    server_loop(remove_client(Client,ClientList),StorePid);
	{request, Client} -> 
	    Client ! {proceed, self()},
	    server_loop(ClientList,StorePid);
	{confirm, Client} ->
	    Client ! {confirm, self()},
	    server_loop(do_actions(Client,ClientList,StorePid),StorePid);
	{action, Client, Act} ->
	    io:format("Received~p from client~p.~n", [Act, Client]),
	    server_loop(add_action(Client, Act, ClientList),StorePid)
    after 50000 ->
	case all_gone(ClientList) of
	    true -> exit(normal);    
	    false -> server_loop(ClientList,StorePid)
	end
    end.

do_actions(Client,[],_) -> Client ! {abort, self()};
do_actions(Client, [{Client, []}|T], _) -> [{Client, []}|T];
do_actions(Client, [{Client, [AH|AT]}|T], StorePid) ->
	case AH of
		{read, Var} ->
			StorePid ! {read, Var},
			receive
			{read_response, Val} ->
				io:format("Client ~p read ~p", [Client, Val])
			end;
		{write, Var, Val} ->
			StorePid ! {write, Var, Val},
			receive
			{write_response} ->
				io:format("Client ~p wrote ~p", [Client, Val])
			end;
		true ->
			io:format("Wrong in do_actions")
	end,
	do_actions(Client, [{Client, [AT]}|T], StorePid);
do_actions(Client, [H|T], StorePid) -> [H|do_actions(Client, T, StorePid)].

store_read(Var,[{Var,Val}|_]) ->
	Val;
store_read(Var,[_|T]) ->
	store_read(Var,T).

store_write(Var,Val,[{Var,_}|T], Client) ->
	Client ! {write_response, Val},
	[{Var,Val}|T];
store_write(Var,Val,[H|T],Client) ->
	[H|store_write(Var,Val,T,Client)].

%% - The values are maintained here
store_loop(ServerPid, Database) -> 
    receive
	{print, ServerPid} -> 
	    io:format("Database status:~n~p.~n",[Database]),
	    store_loop(ServerPid,Database);
	{read, Var} ->
		ServerPid ! {read_response,store_read(Var,Database)},
		store_loop(ServerPid,Database);
	{write, Var, Val} ->
		store_loop(ServerPid,store_write(Var,Val,Database,ServerPid))
				
    end.
%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%% - Low level function to handle lists
add_client(C,T) -> [C|T].

add_action(_,_,[]) -> [];
add_action(C, A, [{C,AL}|T]) -> [{C,AL ++ [A]}|T];
add_action(C, A, [H|T]) -> [H|add_action(C,A,T)].

remove_client(_,[]) -> [];
remove_client(C, [{C,_}|T]) -> T;
remove_client(C, [H|T]) -> [H|remove_client(C,T)].

all_gone([]) -> true;
all_gone(_) -> false.
