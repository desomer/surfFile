import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  group('VibeAskUserRequest.tryFromJson', () {
    test(
      'désérialise un objet standard {"questions": [...]} avec types canoniques et alias (singleChoice, multiSelect, bool, string)',
      () {
        final canonical = VibeAskUserRequest.tryFromJson(<String, Object?>{
          'questions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'layout',
              'title': 'Disposition souhaitée ?',
              'description': 'Structure principale de la page.',
              'type': 'single',
              'options': <String>[' 1 colonne ', '2 colonnes', '1 colonne'],
              'default': '2 colonnes',
            },
            <String, Object?>{
              'id': 'fields',
              'title': 'Champs à inclure',
              'type': 'multi',
              'options': <String>['SIRET', 'TVA', 'IBAN'],
              'default': <String>['SIRET', 'TVA'],
              'allowOther': false,
            },
            <String, Object?>{
              'id': 'rgpd',
              'title': 'Consentement RGPD requis ?',
              'type': 'boolean',
              'default': true,
            },
            <String, Object?>{
              'id': 'cta',
              'title': 'Libellé du bouton principal',
              'type': 'text',
              'default': 'Envoyer la demande',
            },
          ],
        });

        expect(canonical, isNotNull);
        expect(canonical!.questions, hasLength(4));

        final q0 = canonical.questions[0];
        expect(q0.id, 'layout');
        expect(q0.title, 'Disposition souhaitée ?');
        expect(q0.description, 'Structure principale de la page.');
        expect(q0.type, VibeAskUserFieldType.single);
        expect(q0.options, <String>['1 colonne', '2 colonnes']);
        expect(q0.defaultValue, '2 colonnes');
        expect(q0.allowOther, isTrue);

        final q1 = canonical.questions[1];
        expect(q1.id, 'fields');
        expect(q1.type, VibeAskUserFieldType.multi);
        expect(q1.options, <String>['SIRET', 'TVA', 'IBAN']);
        expect(q1.defaultValue, <String>['SIRET', 'TVA']);
        expect(q1.allowOther, isFalse);

        final q2 = canonical.questions[2];
        expect(q2.id, 'rgpd');
        expect(q2.type, VibeAskUserFieldType.boolean);
        expect(q2.options, isEmpty);
        expect(q2.defaultValue, isTrue);
        expect(q2.allowOther, isFalse);

        final q3 = canonical.questions[3];
        expect(q3.id, 'cta');
        expect(q3.type, VibeAskUserFieldType.text);
        expect(q3.options, isEmpty);
        expect(q3.defaultValue, 'Envoyer la demande');
        expect(q3.allowOther, isFalse);

        // Vérifie les alias de types, de clés et d'options {value, label}.
        final aliased = VibeAskUserRequest.tryFromJson(<String, Object?>{
          'fields': <Map<String, Object?>>[
            <String, Object?>{
              'key': 'tone',
              'question': 'Ton visuel ?',
              'subtitle': 'Palette générale',
              'kind': 'singleChoice',
              'choices': <Object>[
                <String, String>{'value': 'corp', 'label': 'Institutionnel'},
                <String, String>{'value': 'mod', 'label': 'Moderne'},
              ],
              'defaultValue': 'mod',
            },
            <String, Object?>{
              'name': 'exports',
              'label': 'Formats exportables',
              'fieldType': 'multiSelect',
              'enum': <String>['CSV', 'PDF', 'XLSX'],
              'initial': 'PDF',
              'allow_other': false,
            },
            <String, Object?>{
              'id': 'dark',
              'prompt': 'Mode sombre par défaut ?',
              'inputType': 'bool',
              'default': 'oui',
            },
            <String, Object?>{
              'id': 'subtitle',
              'title': 'Sous-titre personnalisé',
              'type': 'string',
              'default': 'Portail entreprise',
            },
          ],
        });

        expect(aliased, isNotNull);
        expect(aliased!.questions, hasLength(4));
        expect(aliased.questions[0].id, 'tone');
        expect(aliased.questions[0].type, VibeAskUserFieldType.single);
        expect(aliased.questions[0].options, <String>[
          'Institutionnel',
          'Moderne',
        ]);
        expect(aliased.questions[0].defaultValue, 'Moderne');

        expect(aliased.questions[1].id, 'exports');
        expect(aliased.questions[1].type, VibeAskUserFieldType.multi);
        expect(aliased.questions[1].defaultValue, <String>['PDF']);
        expect(aliased.questions[1].allowOther, isFalse);

        expect(aliased.questions[2].type, VibeAskUserFieldType.boolean);
        expect(aliased.questions[2].defaultValue, isTrue);

        expect(aliased.questions[3].type, VibeAskUserFieldType.text);
        expect(aliased.questions[3].defaultValue, 'Portail entreprise');
      },
    );

    test(
      'accepte une liste directe [...] ainsi qu’un objet JSON Schema {"properties": {...}} et déduplique/plafonne les questions',
      () {
        final fromList = VibeAskUserRequest.tryFromJson(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'dup',
            'title': 'Question 1',
            'options': <String>['A', 'B'],
          },
          <String, Object?>{
            'id': 'dup',
            'title': 'Question 2',
            'type': 'boolean',
          },
          for (var i = 3; i <= 8; i++)
            <String, Object?>{'title': 'Question $i'},
        ]);

        expect(fromList, isNotNull);
        expect(fromList!.questions, hasLength(VibeAskUserRequest.maxQuestions));
        expect(fromList.questions[0].id, 'dup');
        expect(fromList.questions[0].type, VibeAskUserFieldType.single);
        expect(fromList.questions[1].id, 'dup_2');
        expect(fromList.questions[2].id, 'q_3');

        final fromJsonSchema = VibeAskUserRequest.tryFromJson(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'density': <String, Object?>{
              'type': 'string',
              'title': 'Densité d’affichage',
              'enum': <String>['Compacte', 'Confortable'],
              'default': 'Compacte',
            },
            'modules': <String, Object?>{
              'type': 'array',
              'title': 'Modules actifs',
              'items': <String, Object?>{
                'type': 'string',
                'enum': <String>['Facturation', 'CRM', 'Support'],
              },
              'default': <String>['Facturation'],
            },
            'auditTrail': <String, Object?>{
              'type': 'boolean',
              'title': 'Journal d’audit',
              'default': false,
            },
            'companyName': <String, Object?>{
              'type': 'string',
              'title': 'Nom de société par défaut',
            },
          },
        });

        expect(fromJsonSchema, isNotNull);
        expect(fromJsonSchema!.questions, hasLength(4));
        expect(fromJsonSchema.questions[0].id, 'density');
        expect(fromJsonSchema.questions[0].type, VibeAskUserFieldType.single);
        expect(fromJsonSchema.questions[0].options, <String>[
          'Compacte',
          'Confortable',
        ]);
        expect(fromJsonSchema.questions[0].defaultValue, 'Compacte');

        expect(fromJsonSchema.questions[1].id, 'modules');
        expect(fromJsonSchema.questions[1].type, VibeAskUserFieldType.multi);
        expect(fromJsonSchema.questions[1].options, <String>[
          'Facturation',
          'CRM',
          'Support',
        ]);
        expect(fromJsonSchema.questions[1].defaultValue, <String>[
          'Facturation',
        ]);

        expect(fromJsonSchema.questions[2].id, 'auditTrail');
        expect(fromJsonSchema.questions[2].type, VibeAskUserFieldType.boolean);
        expect(fromJsonSchema.questions[2].defaultValue, isFalse);

        expect(fromJsonSchema.questions[3].id, 'companyName');
        expect(fromJsonSchema.questions[3].type, VibeAskUserFieldType.text);
      },
    );

    test(
      'rétrograde gracieusement une question single ou multi sans options valides vers VibeAskUserFieldType.text',
      () {
        final request = VibeAskUserRequest.tryFromJson(<String, Object?>{
          'questions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'emptySingle',
              'title': 'Choisir un modèle',
              'type': 'single',
              'options': <String>['   ', ''],
              'default': 'Standard',
            },
            <String, Object?>{
              'id': 'emptyMulti',
              'title': 'Sélectionner des filtres',
              'type': 'multiSelect',
            },
          ],
        });

        expect(request, isNotNull);
        expect(request!.questions, hasLength(2));

        expect(request.questions[0].type, VibeAskUserFieldType.text);
        expect(request.questions[0].options, isEmpty);
        expect(request.questions[0].defaultValue, 'Standard');
        expect(request.questions[0].allowOther, isFalse);

        expect(request.questions[1].type, VibeAskUserFieldType.text);
        expect(request.questions[1].options, isEmpty);
        expect(request.questions[1].effectiveInitialAnswer(), '');
      },
    );

    test(
      'retourne null pour null, booléens, objets vides ou entrées sans intitulé valide',
      () {
        expect(VibeAskUserRequest.tryFromJson(null), isNull);
        expect(VibeAskUserRequest.tryFromJson(false), isNull);
        expect(VibeAskUserRequest.tryFromJson(true), isNull);
        expect(VibeAskUserRequest.tryFromJson(<String, Object?>{}), isNull);
        expect(VibeAskUserRequest.tryFromJson(<Object?>[]), isNull);
        expect(
          VibeAskUserRequest.tryFromJson(<String, Object?>{
            'questions': <Object?>[],
          }),
          isNull,
        );
        expect(
          VibeAskUserRequest.tryFromJson(<String, Object?>{
            'questions': <Map<String, Object?>>[
              <String, Object?>{'id': 'no-title', 'type': 'text'},
            ],
          }),
          isNull,
        );
        expect(
          VibeAskUserRequest.tryFromJson(
            VibeAskUserRequest(questions: const <VibeAskUserQuestion>[]),
          ),
          isNull,
        );
      },
    );
  });

  group('Réponses par défaut, formatage, sérialisation et égalité', () {
    final sampleRequest = VibeAskUserRequest(
      questions: <VibeAskUserQuestion>[
        VibeAskUserQuestion(
          id: 'layout',
          title: 'Disposition',
          description: 'Colonnes du formulaire',
          type: VibeAskUserFieldType.single,
          options: const <String>['1 colonne', '2 colonnes'],
          defaultValue: '2 colonnes',
        ),
        VibeAskUserQuestion(
          id: 'fields',
          title: 'Champs B2B',
          type: VibeAskUserFieldType.multi,
          options: const <String>['SIRET', 'TVA', 'IBAN'],
          defaultValue: const <String>['SIRET'],
        ),
        VibeAskUserQuestion(
          id: 'rgpd',
          title: 'Case RGPD',
          type: VibeAskUserFieldType.boolean,
          defaultValue: true,
        ),
        VibeAskUserQuestion(
          id: 'cta',
          title: 'Bouton d’action',
          type: VibeAskUserFieldType.text,
          defaultValue: 'Valider',
        ),
      ],
    );

    test(
      'defaultAnswers retourne une carte immuable typée avec repli cohérent quand defaultValue est omis',
      () {
        final defaults = sampleRequest.defaultAnswers();
        expect(defaults, <String, Object?>{
          'layout': '2 colonnes',
          'fields': <String>['SIRET'],
          'rgpd': true,
          'cta': 'Valider',
        });
        expect(() => defaults['other'] = 'x', throwsUnsupportedError);
        expect(
          () => (defaults['fields'] as List<String>).add('IBAN'),
          throwsUnsupportedError,
        );

        final withoutExplicitDefaults = VibeAskUserRequest(
          questions: <VibeAskUserQuestion>[
            VibeAskUserQuestion(
              id: 's',
              title: 'Choix',
              type: VibeAskUserFieldType.single,
              options: const <String>['Premier', 'Second'],
            ),
            VibeAskUserQuestion(
              id: 'm',
              title: 'Multi',
              type: VibeAskUserFieldType.multi,
              options: const <String>['X', 'Y'],
            ),
            VibeAskUserQuestion(
              id: 'b',
              title: 'Bool',
              type: VibeAskUserFieldType.boolean,
            ),
            VibeAskUserQuestion(
              id: 't',
              title: 'Texte',
              type: VibeAskUserFieldType.text,
            ),
          ],
        );

        expect(withoutExplicitDefaults.defaultAnswers(), <String, Object?>{
          's': 'Premier',
          'm': <String>[],
          'b': false,
          't': '',
        });
      },
    );

    test(
      'formatDisplaySummary et formatPromptReply formatent les choix personnalisés, les valeurs par défaut et la consigne anti-boucle ("askUser": null)',
      () {
        final customAnswers = <String, Object?>{
          'layout': 'Grille 3 colonnes',
          'fields': <String>[],
          'rgpd': false,
          'cta': '   ',
        };

        expect(
          sampleRequest.formatDisplaySummary(customAnswers),
          '• Disposition : Grille 3 colonnes\n'
          '• Champs B2B : Aucun\n'
          '• Case RGPD : Non\n'
          '• Bouton d’action : Non précisé',
        );

        final customReply = sampleRequest.formatPromptReply(customAnswers);
        expect(
          customReply,
          startsWith('Réponses aux questions de clarification :\n'),
        );
        expect(customReply, isNot(contains('(valeurs par défaut retenues)')));
        expect(customReply, contains('• Disposition : Grille 3 colonnes'));
        expect(
          customReply,
          endsWith(
            'Génère maintenant directement le patch "vibe" correspondant '
            'sans poser de nouvelles questions ("askUser": null).',
          ),
        );

        final defaultsReply = sampleRequest.formatPromptReply(
          const <String, Object?>{},
          usedDefaults: true,
        );
        expect(
          defaultsReply,
          startsWith(
            'Réponses aux questions de clarification (valeurs par défaut retenues) :\n',
          ),
        );
        expect(defaultsReply, contains('• Disposition : 2 colonnes'));
        expect(defaultsReply, contains('• Champs B2B : SIRET'));
        expect(defaultsReply, contains('• Case RGPD : Oui'));
        expect(defaultsReply, contains('• Bouton d’action : Valider'));
        expect(defaultsReply, contains('("askUser": null)'));
      },
    );

    test(
      'toJson effectue un aller-retour fidèle via tryFromJson et respecte operator == / hashCode',
      () {
        final json = sampleRequest.toJson();
        expect(() => json['extra'] = 1, throwsUnsupportedError);

        final roundTripped = VibeAskUserRequest.tryFromJson(json);
        expect(roundTripped, isNotNull);
        expect(roundTripped, equals(sampleRequest));
        expect(roundTripped!.hashCode, equals(sampleRequest.hashCode));

        final modified = VibeAskUserRequest(
          questions: <VibeAskUserQuestion>[
            sampleRequest.questions[0],
            VibeAskUserQuestion(
              id: 'fields',
              title: 'Champs B2B',
              type: VibeAskUserFieldType.multi,
              options: const <String>['SIRET', 'TVA', 'IBAN'],
              defaultValue: const <String>['SIRET', 'TVA'],
            ),
            sampleRequest.questions[2],
            sampleRequest.questions[3],
          ],
        );
        expect(modified, isNot(equals(sampleRequest)));
      },
    );

    test(
      'VibeQuestioningLevel pilote les directives dynamiques et truncate plafonne le questionnaire',
      () {
        expect(
          VibeQuestioningLevel.fromSliderValue(-2),
          VibeQuestioningLevel.none,
        );
        expect(
          VibeQuestioningLevel.fromSliderValue(0.2),
          VibeQuestioningLevel.none,
        );
        expect(
          VibeQuestioningLevel.fromSliderValue(1.0),
          VibeQuestioningLevel.light,
        );
        expect(
          VibeQuestioningLevel.fromSliderValue(2.0),
          VibeQuestioningLevel.balanced,
        );
        expect(
          VibeQuestioningLevel.fromSliderValue(9.0),
          VibeQuestioningLevel.thorough,
        );

        expect(
          VibeQuestioningLevel.none.promptDirective(afterAskUserReply: false),
          contains('0/3 (Aucun)'),
        );
        expect(
          VibeQuestioningLevel.light.promptDirective(afterAskUserReply: false),
          contains('1/3 (Léger, max 2 questions)'),
        );
        expect(
          VibeQuestioningLevel.balanced.promptDirective(
            afterAskUserReply: false,
          ),
          contains('2/3 (Équilibré, max 4 questions)'),
        );
        expect(
          VibeQuestioningLevel.thorough.promptDirective(
            afterAskUserReply: false,
          ),
          contains('3/3 (Approfondi, 4 à 6 questions)'),
        );
        expect(
          VibeQuestioningLevel.thorough.promptDirective(
            afterAskUserReply: true,
          ),
          contains('Réponses déjà fournies — INTERDICTION'),
        );

        expect(sampleRequest.truncate(0), isNull);
        final truncated2 = sampleRequest.truncate(2);
        expect(truncated2, isNotNull);
        expect(truncated2!.questions.map((q) => q.id), <String>[
          'layout',
          'fields',
        ]);
        expect(sampleRequest.truncate(4), same(sampleRequest));
      },
    );
  });
}
