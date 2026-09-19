% Static component registry for the StarIntel Universe.
%
% component(Name)            — canonical component atom
% component(Name, Path, Role) — submodule path under components/ and role
% upstream(Name, Url, Branch) — canonical public upstream
%
% Private components (e.g. starintel-pro-actors) are NOT registered here;
% they are optional overlays (scripts/add-private-overlay.sh) and must never
% enter public release artifacts.

component(starintel_server).
component(quasar).
component(quasar_ui).
component(vanta).            % distribution identity of upstream zara
component(star_lang).
component(star_kb).
component(star_cl).
component(prolog_rlm).
component(zara).
component(zara_plugins).
component(dotfiles).

component(starintel_server, 'components/starintel-server', service).
component(quasar,            'components/quasar',            control_plane).
component(quasar_ui,         'components/quasar-ui',         ui).
component(star_lang,         'components/star-lang',         language).
component(star_kb,           'components/star-kb',           knowledge).
component(star_cl,           'components/star-cl',           codec).
component(prolog_rlm,        'components/prolog-rlm',        reasoning).
component(vanta,             'components/zara',              agent).
component(zara,              'components/zara',              agent).
component(zara_plugins,      'components/zara-plugins',      agent_plugins).
component(dotfiles,          'components/dotfiles',          defaults).

% vanta is the StarIntel distribution identity of zara: same pin, same path.
:- dynamic(vanta_identity/0).
vanta_identity :- component(vanta, Path, _), component(zara, Path, _).

upstream(starintel_server, 'https://git.starintel.actor/nsaspy/starintel-server.git', master).
upstream(quasar,            'https://git.starintel.actor/nsaspy/quasar.git',            main).
upstream(quasar_ui,         'https://git.starintel.actor/nsaspy/quasar-ui.git',         main).
upstream(star_lang,         'https://git.starintel.actor/nsaspy/star-lang.git',         main).
upstream(star_kb,           'https://git.starintel.actor/nsaspy/star-kb.git',           main).
upstream(star_cl,           'https://git.starintel.actor/nsaspy/star-cl.git',           master).
upstream(prolog_rlm,        'https://git.starintel.actor/nsaspy/prolog-rlm.git',        main).
upstream(zara,              'https://git.starintel.actor/nsaspy/zara.git',              master).
upstream(vanta,             'https://git.starintel.actor/nsaspy/zara.git',              master).
upstream(zara_plugins,      'https://git.starintel.actor/nsaspy/zara-plugins.git',      main).
upstream(dotfiles,          'https://git.starintel.actor/nsaspy/dotfiles.git',          master).

% path_component/2 relates a submodule directory name to its component.
path_component(Path, Name) :-
    component(Name, Path, _).
