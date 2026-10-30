export const DEFAULT_REPOSITORY_ID = '0123456789abcdef0123456789abcdef';

export const DEFAULT_REPOSITORIES: Record<string, { name: string; data: unknown }> = {
	[DEFAULT_REPOSITORY_ID]: {
		name: 'crm_clients.json',
		data: {
			stats: {
				caMensuel: '148 500 €',
				clientsActifs: '42 clients',
				tauxSatisfaction: '98.4 %'
			},
			clients: [
				{
					nom: 'Atelier Lumière SAS',
					secteur: 'Architecture & Design',
					ville: 'Lyon',
					email: 'contact@atelier-lumiere.fr',
					ca: '42 000 €',
					actif: true,
					vip: true,
					notes: 'Client historique, déploiement multi-sites prévu au T3.',
					commandes: [
						{ ref: 'CMD-2026-01', objet: 'Refonte identité & portail web', montant: '18 500 €' },
						{ ref: 'CMD-2026-04', objet: 'Extension module 3D temps réel', montant: '23 500 €' }
					]
				},
				{
					nom: 'NovaTech Robotique',
					secteur: 'Industrie 4.0',
					ville: 'Toulouse',
					email: 'direction@novatech-ind.fr',
					ca: '64 200 €',
					actif: true,
					vip: true,
					notes: 'Contrat de maintenance annuel actif.',
					commandes: [
						{ ref: 'CMD-2026-02', objet: 'Supervision ligne robotisée', montant: '64 200 €' }
					]
				},
				{
					nom: 'Horizons Verts Bio',
					secteur: 'Agroalimentaire',
					ville: 'Nantes',
					email: 'info@horizons-verts.fr',
					ca: '19 800 €',
					actif: true,
					vip: false,
					notes: 'En attente de validation du devis logistique.',
					commandes: [
						{ ref: 'CMD-2026-07', objet: 'Audit chaîne logistique', montant: '19 800 €' }
					]
				},
				{
					nom: 'Boréal Énergie',
					secteur: 'Énergies renouvelables',
					ville: 'Lille',
					email: 'projets@boreal-energie.fr',
					ca: '22 500 €',
					actif: false,
					vip: false,
					notes: 'Projet mis en pause jusqu’au prochain trimestre.',
					commandes: []
				}
			]
		}
	}
};

export const DEFAULT_EXPORT_JSON: Record<string, unknown> = {
	format: 'super_container_layout.default_appearance',
	version: 1,
	groups: ['styles', 'layouts'],
	data: {
		mode: 'light',
		accent: '#5268D9',
		backgroundOpacity: 1,
		windowOpacity: 1,
		windowEffect: 'transparent',
		pageCatalog: {
			homePageId: 'page-dashboard',
			pages: [
				{
					id: 'page-dashboard',
					name: 'Portail CRM — Tableau de bord',
					path: '/',
					defaultParameters: {}
				},
				{
					id: 'page-details',
					name: 'Fiche Client & Commandes',
					path: '/details',
					defaultParameters: {}
				}
			]
		},
		styles: {
			background: {
				color: '#F3F5FA',
				fill: {
					type: 'linear',
					start: '#F4F6FC',
					end: '#E9EEF8',
					angle: 135
				},
				padding: 12
			},
			'kpi-ca': {
				designSystem: 'liquidGlass',
				color: '#FFFFFF',
				radius: 16,
				padding: 18,
				elevation: 4,
				backdropBlur: 16,
				borderWidth: 1,
				borderColor: '#D8E0F5',
				hoverEffect: true
			},
			'kpi-clients': {
				designSystem: 'material',
				color: '#FFFFFF',
				radius: 16,
				padding: 18,
				elevation: 3,
				borderWidths: [0, 0, 0, 4],
				borderColor: '#5268D9'
			},
			'kpi-satisfaction': {
				designSystem: 'neumorphism',
				color: '#EEF2FA',
				radius: 16,
				padding: 18,
				elevation: 6,
				shadowOpacity: 0.22
			},
			'list-clients:item': {
				color: '#FFFFFF',
				radius: 12,
				padding: 12,
				borderWidth: 1,
				borderColor: '#E2E8F4',
				hoverEffect: true,
				states: {
					hover: {
						borderColor: '#8B9DF0',
						elevation: 2
					},
					selected: {
						color: '#EEF1FF',
						borderColor: '#5268D9',
						borderWidth: 2,
						elevation: 3
					}
				}
			},
			'card-editor': {
				color: '#FFFFFF',
				radius: 18,
				padding: 20,
				elevation: 4,
				borderWidth: 1,
				borderColor: '#E5EAF5'
			},
			'card-details-page': {
				color: '#FFFFFF',
				radius: 18,
				padding: 24,
				elevation: 5,
				neon: {
					enabled: true,
					color: '#5268D9',
					intensity: 0.35
				}
			},
			'list-commandes:item': {
				color: '#F8FAFF',
				radius: 10,
				padding: 12,
				borderWidth: 1,
				borderColor: '#DCE3F5'
			}
		},
		behaviors: {
			'btn-open-details': [
				{
					id: 'nav-details',
					trigger: 'click',
					enabled: true,
					action: {
						type: 'goToPage',
						pagePath: '/details',
						pageId: 'page-details',
						pageName: 'Fiche Client & Commandes'
					}
				}
			],
			'btn-back-dashboard': [
				{
					id: 'nav-home',
					trigger: 'click',
					enabled: true,
					action: {
						type: 'goToPage',
						pagePath: '/',
						pageId: 'page-dashboard',
						pageName: 'Portail CRM — Tableau de bord'
					}
				}
			],
			'nav-item-dashboard': [
				{
					id: 'bottom-nav-home',
					trigger: 'click',
					enabled: true,
					action: {
						type: 'goToPage',
						pagePath: '/',
						pageId: 'page-dashboard'
					}
				}
			],
			'nav-item-details': [
				{
					id: 'bottom-nav-details',
					trigger: 'click',
					enabled: true,
					action: {
						type: 'goToPage',
						pagePath: '/details',
						pageId: 'page-details'
					}
				}
			]
		},
		components: {
			root: {
				type: 'scaffold',
				bodyMode: 'standard',
				regions: {
					appBar: true,
					body: true,
					bottomNavigationBar: true
				},
				placements: {
					appBar: [{ id: 'main-appbar', type: 'registry:ApplicationBar' }],
					body: [{ id: 'mainLayout', type: 'registry:Layout' }],
					bottomNavigationBar: [{ id: 'main-bottom-nav', type: 'registry:BottomNavigationBar' }]
				}
			},
			'page-dashboard': {
				type: 'scaffold',
				bodyMode: 'standard',
				regions: {
					appBar: true,
					body: true,
					bottomNavigationBar: true
				},
				placements: {
					appBar: [{ id: 'main-appbar', type: 'registry:ApplicationBar' }],
					body: [{ id: 'mainLayout', type: 'registry:Layout' }],
					bottomNavigationBar: [{ id: 'main-bottom-nav', type: 'registry:BottomNavigationBar' }]
				}
			},
			'main-appbar': {
				type: 'native',
				backgroundColor: '#FFFFFF',
				foregroundColor: '#1B2234',
				elevation: 1,
				toolbarHeight: 60,
				regions: {
					title: true,
					actions: true
				},
				placements: {
					title: [{ id: 'app-title', type: 'registry:Value' }],
					actions: [{ id: 'btn-open-details', type: 'registry:Action' }]
				}
			},
			'app-title': {
				type: 'value',
				text: 'SurfFile Web Renderer — Portail Clients',
				fontSize: 18,
				fontWeight: 'bold',
				color: '#1B2234'
			},
			'btn-open-details': {
				type: 'action',
				kind: 'textAndIcon',
				variant: 'filled',
				label: 'Voir la fiche complète',
				icon: 'open_in_new',
				radius: 10
			},
			'main-bottom-nav': {
				type: 'native',
				backgroundColor: '#FFFFFF',
				selectedItemColor: '#5268D9',
				unselectedItemColor: '#68738D',
				height: 60,
				regions: {
					destinations: true
				},
				placements: {
					destinations: [
						{ id: 'nav-item-dashboard', type: 'registry:Action' },
						{ id: 'nav-item-details', type: 'registry:Action' }
					]
				}
			},
			'nav-item-dashboard': {
				type: 'action',
				kind: 'textAndIcon',
				icon: 'dashboard',
				label: 'Tableau de bord'
			},
			'nav-item-details': {
				type: 'action',
				kind: 'textAndIcon',
				icon: 'folder_shared',
				label: 'Fiche Client'
			},
			mainLayout: {
				type: 'layout',
				positioning: 'zones',
				north: true,
				west: true,
				northSize: 96,
				westSize: 320,
				autoSides: ['north'],
				nw: 'row',
				resizeSides: true,
				zoneAxes: {
					north: 'row',
					west: 'column',
					center: 'column'
				},
				zoneFlows: {
					north: {
						expandSlots: true,
						spacing: 14,
						padding: 4
					},
					west: {
						expandSlots: true,
						spacing: 10,
						padding: 4
					},
					center: {
						expandSlots: true,
						spacing: 12,
						padding: 4
					}
				},
				placements: {
					north: [{ id: 'kpi-grid', type: 'registry:Layout' }],
					west: [{ id: 'list-clients', type: 'registry:ListView' }],
					center: [{ id: 'card-editor', type: 'registry:Card' }]
				}
			},
			'kpi-grid': {
				type: 'layout',
				positioning: 'grid',
				grid: {
					columns: 12,
					rowHeight: 82,
					gap: 12,
					compact: true,
					items: {
						'kpi-ca': { x: 0, y: 0, width: 4, height: 1 },
						'kpi-clients': { x: 4, y: 0, width: 4, height: 1 },
						'kpi-satisfaction': { x: 8, y: 0, width: 4, height: 1 }
					}
				},
				placements: {
					center: [
						{ id: 'kpi-ca', type: 'registry:IterableContent' },
						{ id: 'kpi-clients', type: 'registry:IterableContent' },
						{ id: 'kpi-satisfaction', type: 'registry:IterableContent' }
					]
				}
			},
			'kpi-ca': {
				type: 'layout',
				zoneFlows: { center: { expandSlots: false, spacing: 4 } },
				placements: {
					center: [
						{ id: 'lbl-kpi-ca', type: 'registry:Value' },
						{ id: 'val-kpi-ca', type: 'registry:Value' }
					]
				}
			},
			'lbl-kpi-ca': {
				type: 'value',
				text: 'Chiffre d’affaires mensuel (Liquid Glass)',
				fontSize: 12,
				color: '#64708B'
			},
			'val-kpi-ca': {
				type: 'value',
				binding: `${DEFAULT_REPOSITORY_ID}:stats.caMensuel`,
				fontSize: 22,
				fontWeight: 'bold',
				color: '#202945'
			},
			'kpi-clients': {
				type: 'layout',
				zoneFlows: { center: { expandSlots: false, spacing: 4 } },
				placements: {
					center: [
						{ id: 'lbl-kpi-clients', type: 'registry:Value' },
						{ id: 'val-kpi-clients', type: 'registry:Value' }
					]
				}
			},
			'lbl-kpi-clients': {
				type: 'value',
				text: 'Portefeuille actif (Material 3)',
				fontSize: 12,
				color: '#64708B'
			},
			'val-kpi-clients': {
				type: 'value',
				binding: `${DEFAULT_REPOSITORY_ID}:stats.clientsActifs`,
				fontSize: 22,
				fontWeight: 'bold',
				color: '#5268D9'
			},
			'kpi-satisfaction': {
				type: 'layout',
				zoneFlows: { center: { expandSlots: false, spacing: 4 } },
				placements: {
					center: [
						{ id: 'lbl-kpi-sat', type: 'registry:Value' },
						{ id: 'val-kpi-sat', type: 'registry:Value' }
					]
				}
			},
			'lbl-kpi-sat': {
				type: 'value',
				text: 'Indice de satisfaction (Neumorphism)',
				fontSize: 12,
				color: '#64708B'
			},
			'val-kpi-sat': {
				type: 'value',
				binding: `${DEFAULT_REPOSITORY_ID}:stats.tauxSatisfaction`,
				fontSize: 22,
				fontWeight: 'bold',
				color: '#198754'
			},
			'list-clients': {
				type: 'list',
				binding: {
					repositoryId: DEFAULT_REPOSITORY_ID,
					path: 'clients'
				},
				itemExtent: 72,
				spacing: 8,
				allowAdd: true,
				allowRemove: true,
				template: {
					east: true,
					autoSides: ['east'],
					zoneFlows: {
						center: { expandSlots: false, spacing: 2 },
						east: { expandSlots: false, mainAxisAlignment: 'center' }
					},
					placements: {
						center: [
							{ id: 'row-client-nom', type: 'registry:Value' },
							{ id: 'row-client-secteur', type: 'registry:Value' }
						],
						east: [{ id: 'row-client-ca', type: 'registry:Value' }]
					}
				}
			},
			'row-client-nom': {
				type: 'value',
				binding: 'clients[?].nom',
				fontSize: 15,
				fontWeight: 'semibold',
				color: '#1E2538'
			},
			'row-client-secteur': {
				type: 'value',
				binding: 'clients[?].secteur',
				fontSize: 12,
				color: '#68738D'
			},
			'row-client-ca': {
				type: 'value',
				binding: 'clients[?].ca',
				fontSize: 13,
				fontWeight: 'bold',
				color: '#5268D9'
			},
			'card-editor': {
				type: 'native',
				regions: { child: true },
				placements: {
					child: [{ id: 'tabs-client', type: 'registry:Tab' }]
				}
			},
			'tabs-client': {
				type: 'tab',
				mode: 'static',
				indicatorKind: 'underline',
				indicatorColor: '#5268D9',
				labelColor: '#5268D9',
				unselectedLabelColor: '#68738D',
				placements: {
					tabs: [
						{ id: 'tab-btn-infos', type: 'registry:Action' },
						{ id: 'tab-btn-commandes', type: 'registry:Action' }
					],
					'content:tab-btn-infos': [{ id: 'layout-form-client', type: 'registry:Layout' }],
					'content:tab-btn-commandes': [{ id: 'list-commandes', type: 'registry:ListView' }]
				}
			},
			'tab-btn-infos': {
				type: 'action',
				kind: 'textAndIcon',
				icon: 'badge',
				label: 'Informations Client'
			},
			'tab-btn-commandes': {
				type: 'action',
				kind: 'textAndIcon',
				icon: 'receipt_long',
				label: 'Commandes associées'
			},
			'layout-form-client': {
				type: 'layout',
				zoneFlows: {
					center: {
						expandSlots: false,
						scrollable: true,
						spacing: 14,
						padding: 12
					}
				},
				placements: {
					center: [
						{ id: 'input-nom', type: 'registry:Value' },
						{ id: 'input-secteur', type: 'registry:Value' },
						{ id: 'input-email', type: 'registry:Value' },
						{ id: 'input-ville', type: 'registry:Value' },
						{ id: 'input-actif', type: 'registry:Value' },
						{ id: 'input-vip', type: 'registry:Value' },
						{ id: 'expansible-notes', type: 'registry:Expansible' }
					]
				}
			},
			'input-nom': {
				type: 'value',
				mode: 'input',
				label: 'Raison sociale',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].nom`,
				field: { variant: 'outlined', prefixIcon: 'business', clearButton: true }
			},
			'input-secteur': {
				type: 'value',
				mode: 'input',
				label: 'Secteur d’activité',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].secteur`,
				field: { variant: 'outlined', prefixIcon: 'category' }
			},
			'input-email': {
				type: 'value',
				mode: 'input',
				label: 'Adresse e-mail',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].email`,
				field: { variant: 'filled', prefixIcon: 'email' }
			},
			'input-ville': {
				type: 'value',
				mode: 'input',
				label: 'Ville',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].ville`,
				field: { variant: 'outlined', prefixIcon: 'location_on' }
			},
			'input-actif': {
				type: 'value',
				mode: 'input',
				kind: 'switchControl',
				label: 'Compte client actif',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].actif`
			},
			'input-vip': {
				type: 'value',
				mode: 'input',
				kind: 'checkbox',
				label: 'Priorité grand compte (VIP)',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].vip`
			},
			'expansible-notes': {
				type: 'native',
				initiallyExpanded: true,
				toggleIcon: 'chevron',
				regions: { header: true, body: true },
				placements: {
					header: [{ id: 'lbl-notes-header', type: 'registry:Value' }],
					body: [{ id: 'input-notes', type: 'registry:Value' }]
				}
			},
			'lbl-notes-header': {
				type: 'value',
				text: 'Notes commerciales & suivi',
				fontWeight: 'semibold',
				fontSize: 14
			},
			'input-notes': {
				type: 'value',
				mode: 'input',
				label: 'Observations internes',
				minLines: 2,
				maxLines: 4,
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].notes`,
				field: { variant: 'outlined' }
			},
			'list-commandes': {
				type: 'list',
				binding: {
					repositoryId: DEFAULT_REPOSITORY_ID,
					path: 'clients[?].commandes'
				},
				itemExtent: 58,
				spacing: 8,
				allowAdd: true,
				allowRemove: true,
				emptyText: 'Aucune commande pour ce client',
				template: {
					east: true,
					autoSides: ['east'],
					zoneFlows: {
						center: { expandSlots: false, spacing: 2 },
						east: { expandSlots: false, mainAxisAlignment: 'center' }
					},
					placements: {
						center: [
							{ id: 'cmd-ref', type: 'registry:Value' },
							{ id: 'cmd-objet', type: 'registry:Value' }
						],
						east: [{ id: 'cmd-montant', type: 'registry:Value' }]
					}
				}
			},
			'cmd-ref': {
				type: 'value',
				binding: 'clients[?].commandes[?].ref',
				fontWeight: 'bold',
				fontSize: 13
			},
			'cmd-objet': {
				type: 'value',
				binding: 'clients[?].commandes[?].objet',
				fontSize: 12,
				color: '#5B657E'
			},
			'cmd-montant': {
				type: 'value',
				binding: 'clients[?].commandes[?].montant',
				fontWeight: 'bold',
				color: '#198754'
			},
			// Second page: /details
			'page-details': {
				type: 'scaffold',
				bodyMode: 'singleChildScrollView',
				regions: {
					appBar: true,
					body: true,
					bottomNavigationBar: true
				},
				placements: {
					appBar: [{ id: 'details-appbar', type: 'registry:ApplicationBar' }],
					body: [{ id: 'card-details-page', type: 'registry:IterableContent' }],
					bottomNavigationBar: [{ id: 'main-bottom-nav', type: 'registry:BottomNavigationBar' }]
				}
			},
			'details-appbar': {
				type: 'native',
				backgroundColor: '#FFFFFF',
				foregroundColor: '#1B2234',
				elevation: 1,
				useDefaultNavigation: false,
				regions: {
					leading: true,
					title: true
				},
				placements: {
					leading: [{ id: 'btn-back-dashboard', type: 'registry:Action' }],
					title: [{ id: 'details-title', type: 'registry:Value' }]
				}
			},
			'btn-back-dashboard': {
				type: 'action',
				kind: 'icon',
				variant: 'icon',
				icon: 'arrow_back',
				tooltip: 'Retour au tableau de bord'
			},
			'details-title': {
				type: 'value',
				binding: `${DEFAULT_REPOSITORY_ID}:clients[?].nom`,
				fontSize: 18,
				fontWeight: 'bold'
			},
			'card-details-page': {
				type: 'layout',
				zoneFlows: {
					center: {
						expandSlots: false,
						spacing: 16,
						padding: 8
					}
				},
				placements: {
					center: [
						{ id: 'details-header', type: 'registry:Value' },
						{ id: 'layout-form-client', type: 'registry:Layout' },
						{ id: 'list-commandes', type: 'registry:ListView' }
					]
				}
			},
			'details-header': {
				type: 'value',
				text: 'Vue détaillée — Synchronisée en temps réel avec le repository JSON',
				fontSize: 14,
				color: '#5268D9',
				fontWeight: 'medium'
			}
		}
	}
};
