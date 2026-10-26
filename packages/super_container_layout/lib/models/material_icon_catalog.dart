import 'package:material_ui/material_ui.dart';

/// Catégories d'icônes Material pour le filtrage dans le sélecteur.
enum MaterialIconCategory {
  actions('Actions'),
  navigation('Navigation'),
  communication('Communication'),
  content('Fichiers & Contenu'),
  media('Médias'),
  status('Statut & Alertes'),
  user('Utilisateur & Sécurité'),
  commerce('Commerce & Données');

  const MaterialIconCategory(this.label);

  final String label;
}

/// Entrée immuable du catalogue d'icônes Material.
///
/// Utilise exclusivement des constantes [Icons] afin de préserver le
/// tree-shaking des polices d'icônes en compilation release.
@immutable
class MaterialIconEntry {
  const MaterialIconEntry({
    required this.id,
    required this.icon,
    required this.label,
    required this.category,
    this.keywords = const [],
  });

  final String id;
  final IconData icon;
  final String label;
  final MaterialIconCategory category;
  final List<String> keywords;
}

/// Catalogue enrichi d'icônes Material avec recherche FR/EN et catégories.
abstract final class MaterialIconCatalog {
  static const List<MaterialIconEntry> entries = [
    // --- Actions ---
    MaterialIconEntry(
      id: 'touch_app',
      icon: Icons.touch_app_outlined,
      label: 'Action',
      category: MaterialIconCategory.actions,
      keywords: ['tap', 'click', 'clic', 'bouton', 'appuyer', 'touch'],
    ),
    MaterialIconEntry(
      id: 'smart_button',
      icon: Icons.smart_button_outlined,
      label: 'Bouton',
      category: MaterialIconCategory.actions,
      keywords: ['button', 'cta', 'action'],
    ),
    MaterialIconEntry(
      id: 'add',
      icon: Icons.add,
      label: 'Ajouter',
      category: MaterialIconCategory.actions,
      keywords: ['plus', 'new', 'nouveau', 'creer', 'create'],
    ),
    MaterialIconEntry(
      id: 'add_circle',
      icon: Icons.add_circle_outline,
      label: 'Ajouter (cercle)',
      category: MaterialIconCategory.actions,
      keywords: ['plus', 'new', 'nouveau', 'creer', 'create'],
    ),
    MaterialIconEntry(
      id: 'remove',
      icon: Icons.remove,
      label: 'Retirer',
      category: MaterialIconCategory.actions,
      keywords: ['minus', 'moins', 'reduire', 'enlever'],
    ),
    MaterialIconEntry(
      id: 'edit',
      icon: Icons.edit_outlined,
      label: 'Modifier',
      category: MaterialIconCategory.actions,
      keywords: ['crayon', 'editer', 'pencil', 'write', 'ecrire', 'rename'],
    ),
    MaterialIconEntry(
      id: 'delete',
      icon: Icons.delete_outline,
      label: 'Supprimer',
      category: MaterialIconCategory.actions,
      keywords: ['trash', 'corbeille', 'effacer', 'remove', 'poubelle'],
    ),
    MaterialIconEntry(
      id: 'check',
      icon: Icons.check,
      label: 'Valider',
      category: MaterialIconCategory.actions,
      keywords: ['ok', 'done', 'confirm', 'confirmer', 'oui', 'tick'],
    ),
    MaterialIconEntry(
      id: 'check_circle',
      icon: Icons.check_circle_outline,
      label: 'Validé (cercle)',
      category: MaterialIconCategory.actions,
      keywords: ['ok', 'done', 'succes', 'success', 'valider'],
    ),
    MaterialIconEntry(
      id: 'close',
      icon: Icons.close,
      label: 'Fermer',
      category: MaterialIconCategory.actions,
      keywords: ['cancel', 'annuler', 'croix', 'clear', 'effacer', 'quitter'],
    ),
    MaterialIconEntry(
      id: 'search',
      icon: Icons.search,
      label: 'Rechercher',
      category: MaterialIconCategory.actions,
      keywords: ['find', 'loupe', 'chercher', 'query', 'filtre'],
    ),
    MaterialIconEntry(
      id: 'settings',
      icon: Icons.settings_outlined,
      label: 'Paramètres',
      category: MaterialIconCategory.actions,
      keywords: ['config', 'roue', 'reglages', 'options', 'gear', 'preferences'],
    ),
    MaterialIconEntry(
      id: 'tune',
      icon: Icons.tune,
      label: 'Réglages avancés',
      category: MaterialIconCategory.actions,
      keywords: ['sliders', 'options', 'ajuster', 'filtres', 'parametres'],
    ),
    MaterialIconEntry(
      id: 'refresh',
      icon: Icons.refresh,
      label: 'Actualiser',
      category: MaterialIconCategory.actions,
      keywords: ['reload', 'recharger', 'sync', 'synchroniser'],
    ),
    MaterialIconEntry(
      id: 'autorenew',
      icon: Icons.autorenew,
      label: 'Synchroniser',
      category: MaterialIconCategory.actions,
      keywords: ['sync', 'loop', 'boucle', 'actualiser', 'cycle'],
    ),
    MaterialIconEntry(
      id: 'save',
      icon: Icons.save_outlined,
      label: 'Enregistrer',
      category: MaterialIconCategory.actions,
      keywords: ['disquette', 'sauvegarder', 'floppy', 'store'],
    ),
    MaterialIconEntry(
      id: 'share',
      icon: Icons.share_outlined,
      label: 'Partager',
      category: MaterialIconCategory.actions,
      keywords: ['reseau', 'envoyer', 'social', 'diffuser'],
    ),
    MaterialIconEntry(
      id: 'download',
      icon: Icons.download_outlined,
      label: 'Télécharger',
      category: MaterialIconCategory.actions,
      keywords: ['exporter', 'export', 'recuperer', 'descendre', 'get'],
    ),
    MaterialIconEntry(
      id: 'upload',
      icon: Icons.upload_outlined,
      label: 'Importer',
      category: MaterialIconCategory.actions,
      keywords: ['envoyer', 'import', 'televerser', 'monter', 'publish'],
    ),
    MaterialIconEntry(
      id: 'send',
      icon: Icons.send_outlined,
      label: 'Envoyer',
      category: MaterialIconCategory.actions,
      keywords: ['avion', 'message', 'soumettre', 'submit', 'post'],
    ),
    MaterialIconEntry(
      id: 'copy',
      icon: Icons.content_copy_outlined,
      label: 'Copier',
      category: MaterialIconCategory.actions,
      keywords: ['duplicate', 'dupliquer', 'presse-papier', 'clipboard'],
    ),
    MaterialIconEntry(
      id: 'paste',
      icon: Icons.content_paste_outlined,
      label: 'Coller',
      category: MaterialIconCategory.actions,
      keywords: ['clipboard', 'presse-papier'],
    ),
    MaterialIconEntry(
      id: 'cut',
      icon: Icons.content_cut_outlined,
      label: 'Couper',
      category: MaterialIconCategory.actions,
      keywords: ['ciseaux', 'scissors', 'decouper'],
    ),
    MaterialIconEntry(
      id: 'undo',
      icon: Icons.undo,
      label: 'Annuler',
      category: MaterialIconCategory.actions,
      keywords: ['retour', 'precedent', 'revert', 'back'],
    ),
    MaterialIconEntry(
      id: 'redo',
      icon: Icons.redo,
      label: 'Rétablir',
      category: MaterialIconCategory.actions,
      keywords: ['refaire', 'suivant', 'forward'],
    ),
    MaterialIconEntry(
      id: 'filter_list',
      icon: Icons.filter_list,
      label: 'Filtrer',
      category: MaterialIconCategory.actions,
      keywords: ['trier', 'entonnoir', 'filter', 'refine'],
    ),
    MaterialIconEntry(
      id: 'sort',
      icon: Icons.sort,
      label: 'Trier',
      category: MaterialIconCategory.actions,
      keywords: ['ordre', 'order', 'classement', 'sort'],
    ),
    MaterialIconEntry(
      id: 'print',
      icon: Icons.print_outlined,
      label: 'Imprimer',
      category: MaterialIconCategory.actions,
      keywords: ['imprimante', 'printer', 'papier', 'document'],
    ),
    MaterialIconEntry(
      id: 'qr_code',
      icon: Icons.qr_code_2,
      label: 'Code QR',
      category: MaterialIconCategory.actions,
      keywords: ['scan', 'scanner', 'code-barres', 'barcode'],
    ),
    MaterialIconEntry(
      id: 'auto_awesome',
      icon: Icons.auto_awesome_outlined,
      label: 'IA / Magie',
      category: MaterialIconCategory.actions,
      keywords: ['ai', 'intelligence', 'etoiles', 'sparkles', 'generer', 'magic'],
    ),
    MaterialIconEntry(
      id: 'build',
      icon: Icons.build_outlined,
      label: 'Outils',
      category: MaterialIconCategory.actions,
      keywords: ['cle', 'wrench', 'maintenance', 'reparer', 'tool'],
    ),

    // --- Navigation ---
    MaterialIconEntry(
      id: 'home',
      icon: Icons.home_outlined,
      label: 'Accueil',
      category: MaterialIconCategory.navigation,
      keywords: ['maison', 'house', 'main', 'debut', 'start'],
    ),
    MaterialIconEntry(
      id: 'arrow_back',
      icon: Icons.arrow_back,
      label: 'Retour',
      category: MaterialIconCategory.navigation,
      keywords: ['gauche', 'left', 'precedent', 'previous', 'back'],
    ),
    MaterialIconEntry(
      id: 'arrow_forward',
      icon: Icons.arrow_forward,
      label: 'Suivant',
      category: MaterialIconCategory.navigation,
      keywords: ['droite', 'right', 'next', 'continuer', 'forward'],
    ),
    MaterialIconEntry(
      id: 'arrow_upward',
      icon: Icons.arrow_upward,
      label: 'Haut',
      category: MaterialIconCategory.navigation,
      keywords: ['up', 'monter', 'top', 'fleche'],
    ),
    MaterialIconEntry(
      id: 'arrow_downward',
      icon: Icons.arrow_downward,
      label: 'Bas',
      category: MaterialIconCategory.navigation,
      keywords: ['down', 'descendre', 'bottom', 'fleche'],
    ),
    MaterialIconEntry(
      id: 'chevron_left',
      icon: Icons.chevron_left,
      label: 'Chevron gauche',
      category: MaterialIconCategory.navigation,
      keywords: ['precedent', 'previous', 'left', 'retour'],
    ),
    MaterialIconEntry(
      id: 'chevron_right',
      icon: Icons.chevron_right,
      label: 'Chevron droit',
      category: MaterialIconCategory.navigation,
      keywords: ['suivant', 'next', 'right', 'aller'],
    ),
    MaterialIconEntry(
      id: 'expand_more',
      icon: Icons.expand_more,
      label: 'Déplier',
      category: MaterialIconCategory.navigation,
      keywords: ['bas', 'down', 'ouvrir', 'dropdown', 'chevron'],
    ),
    MaterialIconEntry(
      id: 'expand_less',
      icon: Icons.expand_less,
      label: 'Replier',
      category: MaterialIconCategory.navigation,
      keywords: ['haut', 'up', 'fermer', 'collapse', 'chevron'],
    ),
    MaterialIconEntry(
      id: 'menu',
      icon: Icons.menu,
      label: 'Menu',
      category: MaterialIconCategory.navigation,
      keywords: ['hamburger', 'navigation', 'tiroir', 'drawer', 'barres'],
    ),
    MaterialIconEntry(
      id: 'more_vert',
      icon: Icons.more_vert,
      label: 'Plus (vertical)',
      category: MaterialIconCategory.navigation,
      keywords: ['options', 'menu', 'points', 'dots', 'actions'],
    ),
    MaterialIconEntry(
      id: 'more_horiz',
      icon: Icons.more_horiz,
      label: 'Plus (horizontal)',
      category: MaterialIconCategory.navigation,
      keywords: ['options', 'menu', 'points', 'dots', 'actions'],
    ),
    MaterialIconEntry(
      id: 'open_in_new',
      icon: Icons.open_in_new,
      label: 'Ouvrir',
      category: MaterialIconCategory.navigation,
      keywords: ['externe', 'external', 'lien', 'fenetre', 'window', 'launch'],
    ),
    MaterialIconEntry(
      id: 'fullscreen',
      icon: Icons.fullscreen,
      label: 'Plein écran',
      category: MaterialIconCategory.navigation,
      keywords: ['agrandir', 'expand', 'maximize', 'ecran'],
    ),
    MaterialIconEntry(
      id: 'dashboard',
      icon: Icons.dashboard_outlined,
      label: 'Tableau de bord',
      category: MaterialIconCategory.navigation,
      keywords: ['grille', 'grid', 'accueil', 'overview', 'cartes'],
    ),
    MaterialIconEntry(
      id: 'apps',
      icon: Icons.apps,
      label: 'Applications',
      category: MaterialIconCategory.navigation,
      keywords: ['grille', 'grid', 'catalogue', 'modules'],
    ),
    MaterialIconEntry(
      id: 'location_on',
      icon: Icons.location_on_outlined,
      label: 'Localisation',
      category: MaterialIconCategory.navigation,
      keywords: ['map', 'carte', 'adresse', 'address', 'pin', 'gps', 'lieu'],
    ),
    MaterialIconEntry(
      id: 'map',
      icon: Icons.map_outlined,
      label: 'Carte',
      category: MaterialIconCategory.navigation,
      keywords: ['plan', 'navigation', 'itineraire', 'gps', 'lieu'],
    ),
    MaterialIconEntry(
      id: 'language',
      icon: Icons.language,
      label: 'Langue / Web',
      category: MaterialIconCategory.navigation,
      keywords: ['globe', 'monde', 'world', 'internet', 'site', 'traduction'],
    ),

    // --- Communication ---
    MaterialIconEntry(
      id: 'email',
      icon: Icons.email_outlined,
      label: 'E-mail',
      category: MaterialIconCategory.communication,
      keywords: ['mail', 'courriel', 'message', 'enveloppe', 'contact'],
    ),
    MaterialIconEntry(
      id: 'phone',
      icon: Icons.phone_outlined,
      label: 'Téléphone',
      category: MaterialIconCategory.communication,
      keywords: ['appel', 'call', 'mobile', 'contact', 'tel'],
    ),
    MaterialIconEntry(
      id: 'chat',
      icon: Icons.chat_bubble_outline,
      label: 'Discussion',
      category: MaterialIconCategory.communication,
      keywords: ['message', 'bulle', 'commentaire', 'comment', 'conversation'],
    ),
    MaterialIconEntry(
      id: 'forum',
      icon: Icons.forum_outlined,
      label: 'Forum / Conversation',
      category: MaterialIconCategory.communication,
      keywords: ['chat', 'messages', 'discussion', 'groupe'],
    ),
    MaterialIconEntry(
      id: 'notifications',
      icon: Icons.notifications_outlined,
      label: 'Notifications',
      category: MaterialIconCategory.communication,
      keywords: ['cloche', 'bell', 'alerte', 'rappel', 'reminder'],
    ),
    MaterialIconEntry(
      id: 'Support',
      icon: Icons.support_agent,
      label: 'Support / Assistance',
      category: MaterialIconCategory.communication,
      keywords: ['aide', 'help', 'casque', 'service', 'client', 'agent'],
    ),
    MaterialIconEntry(
      id: 'alternate_email',
      icon: Icons.alternate_email,
      label: 'Arobase (@)',
      category: MaterialIconCategory.communication,
      keywords: ['at', 'mention', 'email', 'identifiant', 'pseudo'],
    ),

    // --- Fichiers & Contenu ---
    MaterialIconEntry(
      id: 'folder',
      icon: Icons.folder_outlined,
      label: 'Dossier',
      category: MaterialIconCategory.content,
      keywords: ['repertoire', 'directory', 'fichiers', 'files'],
    ),
    MaterialIconEntry(
      id: 'folder_open',
      icon: Icons.folder_open_outlined,
      label: 'Dossier ouvert',
      category: MaterialIconCategory.content,
      keywords: ['repertoire', 'directory', 'parcourir', 'browse'],
    ),
    MaterialIconEntry(
      id: 'create_new_folder',
      icon: Icons.create_new_folder_outlined,
      label: 'Nouveau dossier',
      category: MaterialIconCategory.content,
      keywords: ['ajouter', 'repertoire', 'creer', 'folder'],
    ),
    MaterialIconEntry(
      id: 'description',
      icon: Icons.description_outlined,
      label: 'Document',
      category: MaterialIconCategory.content,
      keywords: ['fichier', 'file', 'texte', 'page', 'note', 'article'],
    ),
    MaterialIconEntry(
      id: 'insert_drive_file',
      icon: Icons.insert_drive_file_outlined,
      label: 'Fichier',
      category: MaterialIconCategory.content,
      keywords: ['document', 'page', 'blank', 'nouveau'],
    ),
    MaterialIconEntry(
      id: 'attach_file',
      icon: Icons.attach_file,
      label: 'Pièce jointe',
      category: MaterialIconCategory.content,
      keywords: ['trombone', 'paperclip', 'joindre', 'attachment', 'fichier'],
    ),
    MaterialIconEntry(
      id: 'link',
      icon: Icons.link,
      label: 'Lien',
      category: MaterialIconCategory.content,
      keywords: ['url', 'chaine', 'hyperlien', 'web', 'adresse'],
    ),
    MaterialIconEntry(
      id: 'calendar',
      icon: Icons.calendar_today_outlined,
      label: 'Calendrier',
      category: MaterialIconCategory.content,
      keywords: ['date', 'agenda', 'planning', 'jour', 'evenement', 'event'],
    ),
    MaterialIconEntry(
      id: 'schedule',
      icon: Icons.schedule,
      label: 'Heure / Horloge',
      category: MaterialIconCategory.content,
      keywords: ['time', 'temps', 'duree', 'montre', 'clock', 'historique'],
    ),
    MaterialIconEntry(
      id: 'bookmark',
      icon: Icons.bookmark_border,
      label: 'Marque-page',
      category: MaterialIconCategory.content,
      keywords: ['signet', 'enregistrer', 'favori', 'garder', 'save'],
    ),
    MaterialIconEntry(
      id: 'label',
      icon: Icons.label_outline,
      label: 'Étiquette',
      category: MaterialIconCategory.content,
      keywords: ['tag', 'categorie', 'badge', 'marqueur'],
    ),
    MaterialIconEntry(
      id: 'list',
      icon: Icons.list,
      label: 'Liste',
      category: MaterialIconCategory.content,
      keywords: ['lignes', 'items', 'elements', 'puces', 'menu'],
    ),
    MaterialIconEntry(
      id: 'grid_view',
      icon: Icons.grid_view,
      label: 'Vue grille',
      category: MaterialIconCategory.content,
      keywords: ['mosaique', 'cartes', 'tiles', 'galerie'],
    ),
    MaterialIconEntry(
      id: 'table_chart',
      icon: Icons.table_chart_outlined,
      label: 'Tableau',
      category: MaterialIconCategory.content,
      keywords: ['grille', 'spreadsheet', 'colonnes', 'donnees', 'data'],
    ),
    MaterialIconEntry(
      id: 'code',
      icon: Icons.code,
      label: 'Code',
      category: MaterialIconCategory.content,
      keywords: ['dev', 'developpement', 'script', 'json', 'html', 'balise'],
    ),
    MaterialIconEntry(
      id: 'terminal',
      icon: Icons.terminal,
      label: 'Terminal',
      category: MaterialIconCategory.content,
      keywords: ['console', 'shell', 'commande', 'cli'],
    ),
    MaterialIconEntry(
      id: 'storage',
      icon: Icons.storage_outlined,
      label: 'Base de données',
      category: MaterialIconCategory.content,
      keywords: ['serveur', 'database', 'stockage', 'disque', 'repository'],
    ),
    MaterialIconEntry(
      id: 'cloud',
      icon: Icons.cloud_outlined,
      label: 'Cloud',
      category: MaterialIconCategory.content,
      keywords: ['nuage', 'en ligne', 'serveur', 'sync', 'drive'],
    ),
    MaterialIconEntry(
      id: 'cloud_upload',
      icon: Icons.cloud_upload_outlined,
      label: 'Envoyer vers le cloud',
      category: MaterialIconCategory.content,
      keywords: ['sauvegarder', 'backup', 'upload', 'nuage'],
    ),
    MaterialIconEntry(
      id: 'cloud_download',
      icon: Icons.cloud_download_outlined,
      label: 'Télécharger du cloud',
      category: MaterialIconCategory.content,
      keywords: ['restaurer', 'download', 'nuage'],
    ),
    MaterialIconEntry(
      id: 'archive',
      icon: Icons.archive_outlined,
      label: 'Archiver',
      category: MaterialIconCategory.content,
      keywords: ['boite', 'zip', 'compresser', 'stocker', 'box'],
    ),

    // --- Médias ---
    MaterialIconEntry(
      id: 'play_arrow',
      icon: Icons.play_arrow_outlined,
      label: 'Lecture',
      category: MaterialIconCategory.media,
      keywords: ['play', 'demarrer', 'start', 'video', 'audio', 'lancer'],
    ),
    MaterialIconEntry(
      id: 'pause',
      icon: Icons.pause,
      label: 'Pause',
      category: MaterialIconCategory.media,
      keywords: ['suspendre', 'attendre', 'wait', 'media'],
    ),
    MaterialIconEntry(
      id: 'stop',
      icon: Icons.stop_outlined,
      label: 'Arrêter',
      category: MaterialIconCategory.media,
      keywords: ['stop', 'fin', 'interrompre', 'carre'],
    ),
    MaterialIconEntry(
      id: 'skip_next',
      icon: Icons.skip_next_outlined,
      label: 'Piste suivante',
      category: MaterialIconCategory.media,
      keywords: ['next', 'suivant', 'avancer', 'media'],
    ),
    MaterialIconEntry(
      id: 'skip_previous',
      icon: Icons.skip_previous_outlined,
      label: 'Piste précédente',
      category: MaterialIconCategory.media,
      keywords: ['previous', 'precedent', 'reculer', 'media'],
    ),
    MaterialIconEntry(
      id: 'volume_up',
      icon: Icons.volume_up_outlined,
      label: 'Volume / Son',
      category: MaterialIconCategory.media,
      keywords: ['audio', 'haut-parleur', 'speaker', 'sound', 'musique'],
    ),
    MaterialIconEntry(
      id: 'volume_off',
      icon: Icons.volume_off_outlined,
      label: 'Muet',
      category: MaterialIconCategory.media,
      keywords: ['mute', 'silence', 'audio', 'son'],
    ),
    MaterialIconEntry(
      id: 'mic',
      icon: Icons.mic_none,
      label: 'Microphone',
      category: MaterialIconCategory.media,
      keywords: ['voix', 'voice', 'enregistrer', 'audio', 'parler'],
    ),
    MaterialIconEntry(
      id: 'image',
      icon: Icons.image_outlined,
      label: 'Image / Photo',
      category: MaterialIconCategory.media,
      keywords: ['photo', 'picture', 'galerie', 'illustration', 'visuel'],
    ),
    MaterialIconEntry(
      id: 'photo_camera',
      icon: Icons.photo_camera_outlined,
      label: 'Appareil photo',
      category: MaterialIconCategory.media,
      keywords: ['camera', 'capture', 'photo', 'prendre'],
    ),
    MaterialIconEntry(
      id: 'videocam',
      icon: Icons.videocam_outlined,
      label: 'Vidéo / Caméra',
      category: MaterialIconCategory.media,
      keywords: ['film', 'movie', 'enregistrement', 'visio'],
    ),
    MaterialIconEntry(
      id: 'music_note',
      icon: Icons.music_note_outlined,
      label: 'Musique',
      category: MaterialIconCategory.media,
      keywords: ['audio', 'chanson', 'son', 'note', 'mp3'],
    ),
    MaterialIconEntry(
      id: 'palette',
      icon: Icons.palette_outlined,
      label: 'Apparence / Couleurs',
      category: MaterialIconCategory.media,
      keywords: ['style', 'theme', 'peinture', 'design', 'art', 'color'],
    ),

    // --- Statut & Alertes ---
    MaterialIconEntry(
      id: 'info',
      icon: Icons.info_outline,
      label: 'Information',
      category: MaterialIconCategory.status,
      keywords: ['aide', 'details', 'propos', 'about', 'notice', 'indice'],
    ),
    MaterialIconEntry(
      id: 'help',
      icon: Icons.help_outline,
      label: 'Aide / Question',
      category: MaterialIconCategory.status,
      keywords: ['question', 'faq', 'assistance', 'interrogation', 'support'],
    ),
    MaterialIconEntry(
      id: 'warning',
      icon: Icons.warning_amber_outlined,
      label: 'Alerte',
      category: MaterialIconCategory.status,
      keywords: ['attention', 'danger', 'avertissement', 'prudence', 'caution'],
    ),
    MaterialIconEntry(
      id: 'error',
      icon: Icons.error_outline,
      label: 'Erreur',
      category: MaterialIconCategory.status,
      keywords: ['probleme', 'bug', 'echec', 'exclamation', 'critique'],
    ),
    MaterialIconEntry(
      id: 'favorite',
      icon: Icons.favorite_border,
      label: 'Favori',
      category: MaterialIconCategory.status,
      keywords: ['coeur', 'heart', 'like', 'aimer', 'amour'],
    ),
    MaterialIconEntry(
      id: 'star',
      icon: Icons.star_border,
      label: 'Étoile',
      category: MaterialIconCategory.status,
      keywords: ['note', 'rating', 'favori', 'top', 'important', 'featured'],
    ),
    MaterialIconEntry(
      id: 'thumb_up',
      icon: Icons.thumb_up_outlined,
      label: 'J’aime / Pouce haut',
      category: MaterialIconCategory.status,
      keywords: ['like', 'approuver', 'positif', 'vote', 'bravo'],
    ),
    MaterialIconEntry(
      id: 'bolt',
      icon: Icons.bolt,
      label: 'Éclair / Rapide',
      category: MaterialIconCategory.status,
      keywords: ['flash', 'energie', 'puissance', 'vitesse', 'instant'],
    ),
    MaterialIconEntry(
      id: 'lightbulb',
      icon: Icons.lightbulb_outline,
      label: 'Idée / Astuce',
      category: MaterialIconCategory.status,
      keywords: ['ampoule', 'conseil', 'tip', 'lumiere', 'suggestion'],
    ),
    MaterialIconEntry(
      id: 'flag',
      icon: Icons.flag_outlined,
      label: 'Drapeau / Signaler',
      category: MaterialIconCategory.status,
      keywords: ['objectif', 'etape', 'report', 'marquer', 'jalon'],
    ),
    MaterialIconEntry(
      id: 'verified',
      icon: Icons.verified_outlined,
      label: 'Vérifié / Certifié',
      category: MaterialIconCategory.status,
      keywords: ['badge', 'authentique', 'securise', 'valide', 'officiel'],
    ),

    // --- Utilisateur & Sécurité ---
    MaterialIconEntry(
      id: 'person',
      icon: Icons.person_outline,
      label: 'Profil / Utilisateur',
      category: MaterialIconCategory.user,
      keywords: ['user', 'compte', 'account', 'client', 'humain', 'avatar'],
    ),
    MaterialIconEntry(
      id: 'person_add',
      icon: Icons.person_add_outlined,
      label: 'Ajouter un utilisateur',
      category: MaterialIconCategory.user,
      keywords: ['inscription', 'inviter', 'nouveau', 'membre', 'register'],
    ),
    MaterialIconEntry(
      id: 'group',
      icon: Icons.group_outlined,
      label: 'Groupe / Équipe',
      category: MaterialIconCategory.user,
      keywords: ['users', 'utilisateurs', 'team', 'membres', 'contacts'],
    ),
    MaterialIconEntry(
      id: 'account_circle',
      icon: Icons.account_circle_outlined,
      label: 'Compte (avatar)',
      category: MaterialIconCategory.user,
      keywords: ['profil', 'user', 'utilisateur', 'login'],
    ),
    MaterialIconEntry(
      id: 'badge',
      icon: Icons.badge_outlined,
      label: 'Identité / Badge',
      category: MaterialIconCategory.user,
      keywords: ['carte', 'id', 'nom', 'employe', 'role'],
    ),
    MaterialIconEntry(
      id: 'visibility',
      icon: Icons.visibility_outlined,
      label: 'Afficher',
      category: MaterialIconCategory.user,
      keywords: ['oeil', 'eye', 'voir', 'show', 'apercu', 'view'],
    ),
    MaterialIconEntry(
      id: 'visibility_off',
      icon: Icons.visibility_off_outlined,
      label: 'Masquer',
      category: MaterialIconCategory.user,
      keywords: ['oeil', 'eye', 'cacher', 'hide', 'secret', 'invisible'],
    ),
    MaterialIconEntry(
      id: 'lock',
      icon: Icons.lock_outline,
      label: 'Verrouiller',
      category: MaterialIconCategory.user,
      keywords: ['cadenas', 'mot de passe', 'password', 'securite', 'prive'],
    ),
    MaterialIconEntry(
      id: 'lock_open',
      icon: Icons.lock_open_outlined,
      label: 'Déverrouiller',
      category: MaterialIconCategory.user,
      keywords: ['cadenas', 'ouvert', 'acces', 'unlock', 'public'],
    ),
    MaterialIconEntry(
      id: 'key',
      icon: Icons.key_outlined,
      label: 'Clé / Accès',
      category: MaterialIconCategory.user,
      keywords: ['password', 'secret', 'token', 'identifiant', 'connexion'],
    ),
    MaterialIconEntry(
      id: 'shield',
      icon: Icons.shield_outlined,
      label: 'Protection / Bouclier',
      category: MaterialIconCategory.user,
      keywords: ['securite', 'security', 'privacy', 'confidentialite', 'admin'],
    ),
    MaterialIconEntry(
      id: 'login',
      icon: Icons.login,
      label: 'Connexion',
      category: MaterialIconCategory.user,
      keywords: ['entrer', 'signin', 'connecter', 'session'],
    ),
    MaterialIconEntry(
      id: 'logout',
      icon: Icons.logout,
      label: 'Déconnexion',
      category: MaterialIconCategory.user,
      keywords: ['sortir', 'signout', 'quitter', 'session'],
    ),

    // --- Commerce & Données ---
    MaterialIconEntry(
      id: 'shopping_cart',
      icon: Icons.shopping_cart_outlined,
      label: 'Panier',
      category: MaterialIconCategory.commerce,
      keywords: ['achat', 'boutique', 'store', 'cart', 'commande', 'ecommerce'],
    ),
    MaterialIconEntry(
      id: 'shopping_bag',
      icon: Icons.shopping_bag_outlined,
      label: 'Sac d’achats',
      category: MaterialIconCategory.commerce,
      keywords: ['boutique', 'produit', 'commande', 'shop'],
    ),
    MaterialIconEntry(
      id: 'credit_card',
      icon: Icons.credit_card_outlined,
      label: 'Carte bancaire',
      category: MaterialIconCategory.commerce,
      keywords: ['paiement', 'payment', 'banque', 'cb', 'achat'],
    ),
    MaterialIconEntry(
      id: 'payments',
      icon: Icons.payments_outlined,
      label: 'Paiement / Argent',
      category: MaterialIconCategory.commerce,
      keywords: ['billet', 'monnaie', 'prix', 'tarif', 'cash', 'facture'],
    ),
    MaterialIconEntry(
      id: 'receipt',
      icon: Icons.receipt_long_outlined,
      label: 'Facture / Reçu',
      category: MaterialIconCategory.commerce,
      keywords: ['ticket', 'commande', 'devis', 'invoice', 'historique'],
    ),
    MaterialIconEntry(
      id: 'savings',
      icon: Icons.savings_outlined,
      label: 'Épargne / Budget',
      category: MaterialIconCategory.commerce,
      keywords: ['tirelire', 'banque', 'economie', 'finance', 'argent'],
    ),
    MaterialIconEntry(
      id: 'analytics',
      icon: Icons.analytics_outlined,
      label: 'Statistiques',
      category: MaterialIconCategory.commerce,
      keywords: ['graphique', 'chart', 'donnees', 'rapport', 'kpi', 'mesure'],
    ),
    MaterialIconEntry(
      id: 'trending_up',
      icon: Icons.trending_up,
      label: 'Progression / Hausse',
      category: MaterialIconCategory.commerce,
      keywords: ['croissance', 'evolution', 'courbe', 'stats', 'performance'],
    ),
    MaterialIconEntry(
      id: 'pie_chart',
      icon: Icons.pie_chart_outline,
      label: 'Camembert / Répartition',
      category: MaterialIconCategory.commerce,
      keywords: ['graphique', 'diagramme', 'statistiques', 'part'],
    ),
    MaterialIconEntry(
      id: 'work',
      icon: Icons.work_outline,
      label: 'Travail / Entreprise',
      category: MaterialIconCategory.commerce,
      keywords: ['valise', 'emploi', 'job', 'bureau', 'societe', 'business'],
    ),
    MaterialIconEntry(
      id: 'inventory',
      icon: Icons.inventory_2_outlined,
      label: 'Stock / Inventaire',
      category: MaterialIconCategory.commerce,
      keywords: ['colis', 'boite', 'produit', 'catalogue', 'logistique'],
    ),
    MaterialIconEntry(
      id: 'local_shipping',
      icon: Icons.local_shipping_outlined,
      label: 'Livraison',
      category: MaterialIconCategory.commerce,
      keywords: ['camion', 'transport', 'colis', 'expedition', 'delivery'],
    ),
  ];

  static final Map<String, MaterialIconEntry> byId = {
    for (final entry in entries) entry.id: entry,
  };

  static bool isKnown(String id) => byId.containsKey(id.trim());

  static MaterialIconEntry? tryGet(String? id) =>
      id == null ? null : byId[id.trim()];

  static IconData resolve(String id, {IconData fallback = Icons.touch_app_outlined}) =>
      byId[id.trim()]?.icon ?? fallback;

  static String labelOf(String id) => byId[id.trim()]?.label ?? id.trim();

  /// Normalise une chaîne pour la recherche (minuscules, sans accents, espaces unifiés).
  static String normalizeQuery(String input) {
    final lower = input.trim().toLowerCase();
    if (lower.isEmpty) return '';
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_diacritics[char] ?? char);
    }
    return buffer.toString().replaceAll('_', ' ');
  }

  static const Map<String, String> _diacritics = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
    '’': "'",
  };

  /// Recherche les icônes correspondant à [query] et optionnellement à [category]
  /// ou à un sous-ensemble [allowedIds].
  static List<MaterialIconEntry> search({
    String query = '',
    MaterialIconCategory? category,
    Iterable<String>? allowedIds,
  }) {
    final allowed = allowedIds?.toSet();
    final normalized = normalizeQuery(query);
    final tokens = normalized.isEmpty
        ? const <String>[]
        : normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    return [
      for (final entry in entries)
        if ((allowed == null || allowed.contains(entry.id)) &&
            (category == null || entry.category == category) &&
            _matches(entry, tokens))
          entry,
    ];
  }

  static bool _matches(MaterialIconEntry entry, List<String> tokens) {
    if (tokens.isEmpty) return true;
    final haystack = [
      normalizeQuery(entry.id),
      normalizeQuery(entry.label),
      normalizeQuery(entry.category.label),
      for (final keyword in entry.keywords) normalizeQuery(keyword),
    ].join(' ');
    return tokens.every(haystack.contains);
  }
}
