%%% @doc Contains heuristics to distinguish between well and badly documented
%%% modules and skip rules.
%%% @end
%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_heuristic).

%% API
-export([init/1, should_skip/4]).

%% how many characters in mod summary to consider module well described
-define(MODSUMMARY_NOT_EMPTY, 32).
%% percentage of documented funs to consider module well documented
-define(WELL_DOCUMENTED_PERCENT, 50).
%% how many characters in fun summary to consider single fun documented
-define(FSUMMARY_NOT_EMPTY, 16).

init(Conf0) ->
    Apps = proplists:get_value(apps, Conf0),
    %% Whole build is marked as OTP if any of directories has OTP stdlib nearby
    OTPMode = lists:any(fun is_inside_otp_dir/1, Apps),
    [{heur_otp_mode, OTPMode} | Conf0].

%% @doc Returns true if AppDir is located on the same level as OTP's stdlib
is_inside_otp_dir(AppDir) ->
    Dir = filename:absname_join(AppDir, ".."),
    GenServer1 = filename:join([Dir, "stdlib", "src", "gen_server.erl"]),
    filelib:is_file(GenServer1).

%% @doc Make decision if file should be skipped
-spec should_skip(proplists:proplist(), File :: string(), Summary :: string()
        , Funs :: [tuple()]) -> do_not_skip | badly_documented | is_empty.
should_skip(Conf, File, Summary, Funs) ->
    OTPMode = proplists:get_value(heur_otp_mode, Conf, false),
    should_skip(OTPMode, Conf, File, Summary, Funs).

should_skip(_OTP=false, _Conf, _File, _Sum, _Funs) -> do_not_skip;
should_skip(_OTP=true, Conf, File, Summary, Funs) ->
    HandWritten = is_handwritten(Conf, File),
    HasGoodModuleDoc = length(Summary) > ?MODSUMMARY_NOT_EMPTY,
    case HandWritten or HasGoodModuleDoc of
        true ->
            %% no skip if handwritten or has nonempty module doc
            do_not_skip;
        false ->
            %% remaining reason to skip: bad docs (less than given % of funs
            %% have empty documentation)
            check_if_documented(Funs)
    end.

%% @private
%% @doc Checks if File is inside one of the source directories (apps in Conf)
is_handwritten(Conf, File) ->
    Apps = proplists:get_value(apps, Conf),
    lists:any(fun(X) -> is_located_under(X, File) end, Apps).

%% @private
is_located_under(File, Base) ->
    BaseParts = filename:split(Base),
    FileParts = filename:split(filename:dirname(File)),
    case FileParts of
        [BaseParts | _] ->
            true; % dir which contains XML file begins with base
        _ ->
            false
    end.

%% @private
%% @doc Given the parsed fun list, checks the percentage of documented funs with
%% non-empty fsummary
-spec check_if_documented([tuple()]) -> is_empty | badly_documented | do_not_skip.
check_if_documented([]) -> is_empty; % empty, do not want
check_if_documented(Funs) ->
    %% Must have non-empty docs
    Documented = lists:filter(
        fun(["fun", _, _, Doc0]) ->
            Doc = string:strip(Doc0, both, $ ),
            length(Doc) > ?FSUMMARY_NOT_EMPTY;
            (_) -> false
          end,
        Funs),
    %% Documented funs are at least 75% of all funs
    case length(Documented) * 100 div length(Funs) < ?WELL_DOCUMENTED_PERCENT of
        true -> badly_documented;
        false -> do_not_skip
    end.
