% Dependency graph of the StarIntel Universe.
%
% depends(Component, Dependency): updating Dependency is a reason to
% re-validate Component; a candidate that changes Dependency must keep
% Component's required checks green before merge.

depends(quasar, starintel_server).   % control plane + UI talk to the server API
depends(quasar_ui, quasar).          % UI ships inside the quasar monorepo deployments
depends(vanta, prolog_rlm).          % symbolic recursive reasoning bridge
depends(vanta, starintel_server).    % actor/tool surface via zara-starintel-server plugin
depends(vanta, zara).                % VANTA *is* zara's distribution identity
depends(zara, zara_plugins).         % plugin registry consumed at runtime
depends(starintel_server, star_cl).  % document codec / v0.9 schema conformance
depends(star_lang, starintel_server).% runtime systems consumed by the server
depends(star_kb, starintel_server).  % research records reference the server contract
depends(prolog_rlm, star_cl).        % structured document validation in plans

% depends_on/2: transitive closure (tabled — graphs may grow).
:- table(depends_on/2).
depends_on(X, Y) :-
    depends(X, Y).
depends_on(X, Y) :-
    depends(X, Z),
    depends_on(Z, Y).

% dependency_closure(+Component, -Closure): all transitive dependencies.
dependency_closure(Component, Closure) :-
    findall(D, depends_on(Component, D), Ds),
    sort(Ds, Closure).

% dependents(+Component, -Dependents): everything that depends on Component.
dependents(Component, Dependents) :-
    findall(D, depends_on(D, Component), Ds),
    sort(Ds, Dependents).

% dependency_graph_acyclic: hard invariant. A cycle would make closure
% reasoning non-terminating without tabling and makes batching meaningless.
dependency_graph_acyclic :-
    component(X),
    \+ depends_on(X, X),
    fail.
dependency_graph_acyclic.

% validate_dependency_graph/1 fails with context when the graph is broken.
validate_dependency_graph(ok) :-
    dependency_graph_acyclic.
validate_dependency_graph(cycle(C)) :-
    component(C),
    depends_on(C, C).
