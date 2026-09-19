% Control-plane PlUnit suite.
% Canonical runner: scripts/run-prolog-policy.sh  (also `make prolog`)
%
% NOTE: dynamic control-plane facts (pin/3, check/2, revision_note/2,
% artifact/3) live in `user`; tests must qualify dynamic updates as
% user:Goal or PlUnit would create module-local predicates.

:- use_module(library(plunit)).

:- ensure_loaded(universe).

clear_user_facts :-
    retractall(user:pin(_, _, _)),
    retractall(user:upstream_head(_, _)),
    retractall(user:revision_note(_, _)),
    retractall(user:check(_, _)),
    retractall(user:artifact(_, _, _)).

% Structural invariant: every registered component has a .gitmodules entry
% and every .gitmodules entry is registered (no orphan submodules).
submodule_paths(Paths) :-
    read_file_to_string('.gitmodules', String, []),
    split_string(String, "\n", "\r", Lines),
    findall(P,
            ( member(Line, Lines),
              split_string(Line, "=", " \t", ["path", Ps]),
              atom_string(P, Ps) ),
            Paths).

registry_paths(Paths) :-
    findall(P, component(_, P, _), Ps),
    sort(Ps, Paths).

path_share_count(P, C) :-
    aggregate_all(count, component(_, P, _), C).

:- begin_tests(structure).

test(gitmodules_matches_registry) :-
    submodule_paths(Ps),
    sort(Ps, Sorted),
    registry_paths(Sorted).

test(components_have_upstream) :-
    forall(component(C), upstream(C, _, _)).

test(vanta_is_zara_identity) :-
    component(vanta, Path, agent),
    component(zara, Path, agent).

test(component_paths_exist) :-
    forall(component(_, Path, _), exists_directory(Path)).

test(no_unexpected_duplicate_component_paths) :-
    % vanta/zara intentionally alias one path; no OTHER path may repeat.
    forall(( component(_, P, _),
             path_share_count(P, C),
             C > 1 ),
           P == 'components/zara').

:- end_tests(structure).

:- begin_tests(dependencies).

test(graph_is_acyclic) :-
    dependency_graph_acyclic.

test(closure_quasar_includes_server) :-
    depends_on(quasar, starintel_server).

test(closure_vanta_includes_plugins) :-
    depends_on(vanta, zara_plugins).

test(dependents_of_server) :-
    dependents(starintel_server, Ds),
    member(quasar, Ds),
    member(vanta, Ds),
    !.

test(dependency_closure_validates) :-
    validate_dependency_graph(ok).

:- end_tests(dependencies).

% ---- shared cleanups (user-module) ----

update_policy_cleanup :-
    retractall(user:pin(_, _, _)),
    retractall(user:upstream_head(_, _)),
    retractall(user:revision_note(_, _)).

merge_policy_cleanup :-
    retractall(user:pin(_, _, _)),
    retractall(user:upstream_head(_, _)),
    retractall(user:revision_note(_, _)),
    retractall(user:check(_, _)).

% ---- shared test fixtures (user-module, used across blocks) ----

tpin_quasar :-
    assertz(user:pin(quasar, 'a000000000000000000000000000000000000000', main)).
tpin_server :-
    assertz(user:pin(starintel_server, 'a000000000000000000000000000000000000000', master)).
thead(C, H) :-
    assertz(user:upstream_head(C, H)).
tgreen_universe_checks :-
    forall(required_check(universe, C),
           assertz(user:check(C, green))).
tgreen_server_change :-
    tpin_server,
    thead(starintel_server, 'b000000000000000000000000000000000000000'),
    forall(required_for_change(starintel_server, C),
           assertz(user:check(C, green))),
    forall(( dependents(starintel_server, Ds), member(D, Ds) ),
           assertz(user:revision_note(universe, note(revalidates(D))))).
tserver_change([c(starintel_server,
                  'a000000000000000000000000000000000000000',
                  'b000000000000000000000000000000000000000')]).

:- begin_tests(update_policy).

test(candidate_allowed_when_head_moves, [cleanup(update_policy_cleanup)]) :-
    tpin_quasar,
    thead(quasar, 'b000000000000000000000000000000000000000'),
    candidate_allowed(quasar,
                      'a000000000000000000000000000000000000000',
                      'b000000000000000000000000000000000000000').

test(candidate_denied_for_unknown_component, [cleanup(update_policy_cleanup)]) :-
    tpin_quasar,
    \+ catch(candidate_allowed(quasaar,
                               'a000000000000000000000000000000000000000',
                               'b000000000000000000000000000000000000000'),
            _, fail).

test(candidate_denied_when_not_a_change, [cleanup(update_policy_cleanup)]) :-
    tpin_quasar,
    thead(quasar, 'a000000000000000000000000000000000000000'),
    \+ catch(candidate_allowed(quasar,
                               'a000000000000000000000000000000000000000',
                               'a000000000000000000000000000000000000000'),
            _, fail).

test(candidate_denied_for_short_sha, [cleanup(update_policy_cleanup)]) :-
    tpin_quasar,
    thead(quasar, 'b000000000000000000000000000000000000000'),
    \+ catch(candidate_allowed(quasar,
                               'a000000000000000000000000000000000000000',
                               'deadbeef'),
            _, fail).

test(candidate_denied_when_from_drifts_from_pin, [cleanup(update_policy_cleanup)]) :-
    tpin_quasar,
    thead(quasar, 'b000000000000000000000000000000000000000'),
    \+ catch(candidate_allowed(quasar,
                               'c000000000000000000000000000000000000000',
                               'b000000000000000000000000000000000000000'),
            _, fail).

test(dependency_closure_valid_with_revalidation_note, [cleanup(update_policy_cleanup)]) :-
    forall(( dependents(starintel_server, Ds), member(D, Ds) ),
           assertz(user:revision_note(universe, note(revalidates(D))))),
    dependency_closure_valid([c(starintel_server,
                                'a000000000000000000000000000000000000000',
                                'b000000000000000000000000000000000000000')]).

test(dependency_closure_invalid_without_revalidation, [cleanup(update_policy_cleanup)]) :-
    \+ catch(dependency_closure_valid(
                 [c(starintel_server,
                    'a000000000000000000000000000000000000000',
                    'b000000000000000000000000000000000000000')]),
             _, fail).

test(batch_allowed, [cleanup(update_policy_cleanup)]) :-
    tpin_server,
    thead(starintel_server, 'b000000000000000000000000000000000000000'),
    assertz(user:pin(star_lang, 'a000000000000000000000000000000000000000', main)),
    thead(star_lang, 'b000000000000000000000000000000000000000'),
    forall(( dependents(starintel_server, Ds), member(D, Ds) ),
           assertz(user:revision_note(universe, note(revalidates(D))))),
    batch_allowed([c(star_lang,
                     'a000000000000000000000000000000000000000',
                     'b000000000000000000000000000000000000000'),
                   c(starintel_server,
                     'a000000000000000000000000000000000000000',
                     'b000000000000000000000000000000000000000')]).

test(bisect_groups_splits, [cleanup(update_policy_cleanup)]) :-
    bisect_groups([a, b, c, d], [L, R]),
    !,
    length(L, 2),
    length(R, 2).

:- end_tests(update_policy).

:- begin_tests(merge_policy).

test(merge_allowed_when_everything_green, [cleanup(merge_policy_cleanup)]) :-
    tgreen_universe_checks,
    tgreen_server_change,
    tserver_change(Change),
    merge_allowed(Change).

test(merge_denied_when_check_red, [cleanup(merge_policy_cleanup)]) :-
    tgreen_universe_checks,
    retract(user:check(unit, green)),
    assertz(user:check(unit, red)),
    tgreen_server_change,
    tserver_change(Change),
    \+ merge_allowed(Change).

test(merge_denied_when_component_check_missing, [cleanup(merge_policy_cleanup)]) :-
    tgreen_universe_checks,
    tpin_server,
    thead(starintel_server, 'b000000000000000000000000000000000000000'),
    forall(( dependents(starintel_server, Ds), member(D, Ds) ),
           assertz(user:revision_note(universe, note(revalidates(D))))),
    tserver_change(Change),
    catch(\+ merge_allowed(Change),
          error(policy_missing_fact(_), _),
          true).

test(merge_denial_explains, [cleanup(merge_policy_cleanup)]) :-
    tgreen_universe_checks,
    retract(user:check(actor_matrix, green)),
    assertz(user:check(actor_matrix, red)),
    tserver_change(Change),
    merge_denial(Change, Reasons),
    !,
    member(required_check_not_green(actor_matrix, red), Reasons).

:- end_tests(merge_policy).

:- begin_tests(release_policy).

green_checks :-
    forall(required_check(universe, C), assertz(user:check(C, green))).

test(release_denied_without_artifacts, [cleanup(release_policy_cleanup)]) :-
    green_checks,
    catch(\+ release_allowed(universe),
          error(policy_missing_artifact(_), _),
          true).

test(release_denied_without_manifest, [cleanup(release_policy_cleanup)]) :-
    green_checks,
    assertz(user:artifact(iso_x86_64, 'StarIntel-OS.iso', deadbeef)),
    \+ release_allowed(universe).

test(release_denial_reasons_lists_missing, [cleanup(release_policy_cleanup)]) :-
    release_denial(Reasons),
    !,
    member(manifest_missing, Reasons).

:- end_tests(release_policy).

:- begin_tests(deployment_policy).

test(chain_advances_one_stage, [cleanup(deployment_cleanup)]) :-
    deployment_allowed(candidate, integration),
    deployment_allowed(integration, staging),
    deployment_allowed(staging, release).

test(no_stage_skipping, [cleanup(deployment_cleanup)]) :-
    \+ deployment_allowed(candidate, staging),
    \+ deployment_allowed(candidate, release),
    \+ deployment_allowed(integration, release).

test(no_backwards, [cleanup(deployment_cleanup)]) :-
    \+ deployment_allowed(release, staging).

test(staging_needs_smoke_note, [cleanup(deployment_cleanup)]) :-
    assertz(user:revision_note(universe, note(deployed(integration, abc123)))),
    forall(required_check(universe, C), assertz(user:check(C, green))),
    \+ staging_allowed(abc123),
    assertz(user:revision_note(abc123, note(staging_smoke_green))),
    staging_allowed(abc123).

:- end_tests(deployment_policy).
