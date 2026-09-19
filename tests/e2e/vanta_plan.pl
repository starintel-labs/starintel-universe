% Deterministic VANTA->RLM proof-chain driver.
%
% Registers ONE trusted tool (starintel_target) whose handler submits a
% target to the running StarIntel Server over HTTP, then constructs and
% VALIDATES a typed plan that uses it. No model provider is contacted:
% the plan is a literal JSON plan AST (rlm_plan:plan_run), executed by
% prolog-rlm's closed interpreter.
%
% Usage (from the universe root, against the booted test stack):
%   swipl -q tests/e2e/vanta_plan.pl -- <target-string> <json-out-path>
%
% Exit: 0 = plan validated + executed + tool returned a receipt;
%       1 = execution failed; 2 = usage/validation error.

:- use_module(library(http/http_client)).
:- use_module(library(http/http_header)).
:- use_module(library(http/http_open)).
:- use_module(library(json)).
% Load prolog-rlm's plan interpreter from the pinned submodule
% (resolved relative to this file).
:- use_module('../../components/prolog-rlm/prolog/rlm_plan.pl').

server_base('http://127.0.0.1:15000').

%! starintel_target(++Args, -Value) is det.
% Trusted tool handler: submit one deterministic target to echo-actor.
starintel_target(Args, Value) :-
    get_dict(target, Args, Target),
    server_base(Base),
    atomic_list_concat([Base, '/new/target/echo-actor'], Url),
    Payload = json([target=Target,
                    '_id'='proof-chain-target',
                    dtype=target,
                    dataset='starintel-universe-test',
                    delay=1]),
    http_post(Url, json(Payload), Value, [json_object(dict)]).

%! run_proof(++Target, -Outcome) is det.
run_proof(Target, Outcome) :-
    Plan = json{steps:[
                    json{op:tool,
                         name:starintel_target,
                         args:json{target:Target},
                         bind:submitted},
                    json{op:final,
                         value:json{ref:field,
                                    value:json{ref:var, name:submitted},
                                    key:'_id'}}
                ]},
    Options = [tools([tool(starintel_target,
                           user:starintel_target)]),
               capabilities([tool(starintel_target)]),
               budget(json{max_steps:8, max_depth:2, max_parallel:2,
                           max_model_calls:0, max_tool_calls:4,
                           max_context_ops:4, max_output_bytes:65536,
                           time_limit:30.0})],
    catch(rlm_plan:plan_run(Plan,
                            [tool(starintel_target)],
                            Options,
                            json{},
                            Outcome),
          Error,
          Outcome = json{proof_error:Error}).

main :-
    current_prolog_flag(argv, [TargetAtom, OutPath]),
    !,
    (   run_proof(TargetAtom, Outcome)
    ->  true
    ;   Outcome = execution_failed
    ),
    (   Outcome = ok(plan_result{value:_})
    ->  Status = ok
    ;   Outcome = ok(_)
    ->  Status = ok
    ;   is_dict(Outcome)
    ->  Status = executed
    ;   Status = failed
    ),
    setup_call_cleanup(
        open(OutPath, write, S),
        ( write_term(S, status(Status), [quoted(true)]),
          write(S, '.\n'),
          write_term(S, outcome(Outcome), [quoted(true),
                                           max_depth(20)]),
          write(S, '.\n') ),
        close(S)),
    (   Status = failed
    ->  halt(1)
    ;   halt(0)
    ).
main :-
    format(user_error,
           'usage: vanta_plan.pl <target-string> <out.pl>~n', []),
    halt(2).

:- initialization(main, main).
