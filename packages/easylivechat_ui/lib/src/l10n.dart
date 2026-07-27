import 'dart:ui' show PlatformDispatcher;

/// SDK "chrome" strings for the prebuilt UI (`Send`, `Rate your chat`, …).
///
/// These are the framework's own labels — distinct from tenant-authored copy
/// (`welcomeTitle`, pre-chat field labels, `offlineMessage`) which is rendered
/// **verbatim** and never localized. We ship all 12 product locales to match
/// the dashboard (`ar ckb de en es fr hi it kmr pt tr ur zh`) and fall back to
/// English for any missing key/locale — never hardcode English at the call
/// site (project i18n rule).
///
/// Resolution: an explicit locale (from `EasyLiveChatConfig.locale` /
/// `WidgetConfig.locale`) wins; otherwise the platform locale; otherwise `en`.
/// Matching is by the language subtag only (e.g. `pt-BR` → `pt`).
class ElcStrings {
  final String _lang;
  const ElcStrings._(this._lang);

  /// Host-provided overrides keyed by string key (e.g. `'send'`,
  /// `'typeAMessage'`). When a key is present here it wins over the built-in
  /// localized table for EVERY locale — lets a host fully own the chrome
  /// wording/translation. Keys not provided fall back to the built-in tables.
  ///
  /// Set once (e.g. via `EasyLiveChatScreen(strings: {...})`, or directly):
  /// ```dart
  /// ElcStrings.overrideAll({'send': 'بنێرە', 'typeAMessage': 'پەیامێک بنووسە'});
  /// ```
  static Map<String, String> _overrides = const {};

  /// Replace the host string overrides (merges over the built-in table). Pass an
  /// empty map to clear.
  static void overrideAll(Map<String, String> strings) {
    _overrides = Map<String, String>.unmodifiable(strings);
  }

  /// Host-forced chrome locale (e.g. the host app's current locale). Wins over
  /// both the passed locale and the server workspace locale — the server often
  /// returns its own default (e.g. `en`) regardless of the visitor's app
  /// language, so a host that knows its locale should set this.
  static String? _hostLocale;

  /// Force the chrome locale from the host app. Pass null to clear and fall back
  /// to the server/device locale.
  static void setLocale(String? code) {
    _hostLocale = code;
  }

  /// Resolve strings: host-forced locale → [localeCode] (server/config) →
  /// device locale → English.
  factory ElcStrings.of(String? localeCode) {
    final host = _normalize(_hostLocale);
    if (host != null && _table.containsKey(host)) {
      return ElcStrings._(host);
    }
    final explicit = _normalize(localeCode);
    if (explicit != null && _table.containsKey(explicit)) {
      return ElcStrings._(explicit);
    }
    final device = _normalize(
      PlatformDispatcher.instance.locale.languageCode,
    );
    if (device != null && _table.containsKey(device)) {
      return ElcStrings._(device);
    }
    return const ElcStrings._('en');
  }

  static String? _normalize(String? code) {
    if (code == null) return null;
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return null;
    // language subtag only: pt-BR / pt_br / zh-Hans → pt / zh
    final lang = c.split(RegExp(r'[-_]')).first;
    if (lang.isEmpty) return null;
    // Kurdish: `ckb` (Central Kurdish / Sorani) and `kmr` (Northern Kurdish /
    // Kurmanji / Badini) each have their own table. `ku` is the deprecated
    // macrolanguage code the platform used for Sorani; still accepted here so
    // an older host, or a server row not yet migrated, keeps working.
    if (lang == 'ku') return 'ckb';
    return lang;
  }

  String _t(String key) {
    final o = _overrides[key];
    if (o != null) return o;
    final m = _table[_lang] ?? _table['en']!;
    return m[key] ?? _table['en']![key] ?? key;
  }

  // ── composer / thread ──
  String get send => _t('send');
  String get typeAMessage => _t('typeAMessage');
  String get attach => _t('attach');
  String get attachImage => _t('attachImage');
  String get attachFile => _t('attachFile');
  String get agentTyping => _t('agentTyping');
  String get loadOlder => _t('loadOlder');
  String get mediaUnavailable => _t('mediaUnavailable');
  String get download => _t('download');
  String get image => _t('image');
  String get attachment => _t('attachment');
  String get sendFailedRetry => _t('sendFailedRetry');
  String get sending => _t('sending');

  // ── pre-chat ──
  String get startChat => _t('startChat');
  String get fieldRequired => _t('fieldRequired');
  String get invalidEmail => _t('invalidEmail');
  String get invalidNumber => _t('invalidNumber');
  String get invalidOption => _t('invalidOption');
  String get selectAnOption => _t('selectAnOption');
  String get somethingWentWrong => _t('somethingWentWrong');
  String get retry => _t('retry');
  String get couldNotConnect => _t('couldNotConnect');

  // ── feedback (CSAT) ──
  String get rateYourChat => _t('rateYourChat');
  String get rateHint => _t('rateHint');
  String get addAComment => _t('addAComment');
  String get submit => _t('submit');
  String get thanksForFeedback => _t('thanksForFeedback');

  // ── offline form ──
  String get yourName => _t('yourName');
  String get yourEmail => _t('yourEmail');
  String get yourMessage => _t('yourMessage');
  String get sendMessage => _t('sendMessage');
  String get offlineThanks => _t('offlineThanks');

  /// Banner shown while the workspace is closed. The visitor can still write —
  /// the message waits for the team — so this informs rather than blocks.
  String get closedNotice => _t('closedNotice');

  /// Appended to [closedNotice] when the server tells us when we reopen.
  String get backAt => _t('backAt');

  /// Distinct from [closedNotice]: we ARE open, there's just nobody free.
  String get noAgentsNotice => _t('noAgentsNotice');

  /// Used instead of [closedNotice] when the closure has a name.
  String get closedForLabel => _t('closedForLabel');

  /// Headline on the closed screen. Short and unambiguous — the visitor should
  /// know they cannot be helped right now before reading a word of body copy.
  String get unavailableTitle => _t('unavailableTitle');

  // ── leaving the chat ──

  /// Asked before the visitor backs out of the chat, so a stray back gesture
  /// mid-conversation doesn't drop them out of it.
  String get exitChatTitle => _t('exitChatTitle');
  String get exitChatConfirm => _t('exitChatConfirm');
  String get exitChatCancel => _t('exitChatCancel');

  /// Map a server/SDK error code to a human, localized message (best effort).
  String forErrorCode(String code) {
    switch (code) {
      case 'REQUIRED':
        return fieldRequired;
      case 'INVALID_EMAIL':
        return invalidEmail;
      case 'INVALID_NUMBER':
        return invalidNumber;
      case 'INVALID_OPTION':
        return invalidOption;
      case 'INVALID_RATING':
        // The post-chat survey's rating field. "Please pick a rating" and
        // "this field is required" are the same instruction to a visitor
        // staring at an unset row of stars.
        return fieldRequired;
      default:
        return somethingWentWrong;
    }
  }

  static const Map<String, Map<String, String>> _table = {
    'en': {
      'send': 'Send',
      'typeAMessage': 'Type a message',
      'attach': 'Attach',
      'attachImage': 'Photo',
      'attachFile': 'File',
      'agentTyping': 'Typing…',
      'loadOlder': 'Load earlier messages',
      'mediaUnavailable': 'Media unavailable',
      'download': 'Download',
      'image': 'Image',
      'attachment': 'Attachment',
      'sendFailedRetry': 'Not sent. Tap to retry.',
      'sending': 'Sending…',
      'startChat': 'Start chat',
      'fieldRequired': 'This field is required',
      'invalidEmail': 'Enter a valid email address',
      'invalidNumber': 'Enter a valid number',
      'invalidOption': 'Choose one of the options',
      'selectAnOption': 'Select…',
      'somethingWentWrong': 'Something went wrong. Please try again.',
      'retry': 'Retry',
      'couldNotConnect': "Couldn't connect. Check your connection and try again.",
      'rateYourChat': 'Rate your chat',
      'rateHint': 'How was your conversation?',
      'addAComment': 'Add a comment (optional)',
      'submit': 'Submit',
      'thanksForFeedback': 'Thanks for your feedback!',
      'yourName': 'Your name',
      'yourEmail': 'Your email',
      'yourMessage': 'Your message',
      'sendMessage': 'Send message',
      'closedNotice': "Our team is offline right now. Leave your message and we'll reply as soon as we're back.",
      'backAt': "We're back at {time}.",
      'noAgentsNotice': "Everyone's busy right now. Leave a message and we'll reply shortly.",
      'closedForLabel': "We're closed for {label}.",
      'unavailableTitle': "We're not available right now",
      'offlineThanks': "Thanks! We'll get back to you.",
      'exitChatTitle': 'Do you really want to close this chat?',
      'exitChatConfirm': 'Close chat',
      'exitChatCancel': 'Cancel',
    },
    'ar': {
      'send': 'إرسال',
      'typeAMessage': 'اكتب رسالة',
      'attach': 'إرفاق',
      'attachImage': 'صورة',
      'attachFile': 'ملف',
      'agentTyping': 'يكتب…',
      'loadOlder': 'تحميل الرسائل السابقة',
      'mediaUnavailable': 'الوسائط غير متوفرة',
      'download': 'تنزيل',
      'image': 'صورة',
      'attachment': 'مرفق',
      'sendFailedRetry': 'لم يتم الإرسال. اضغط لإعادة المحاولة.',
      'sending': 'جارٍ الإرسال…',
      'startChat': 'بدء المحادثة',
      'fieldRequired': 'هذا الحقل مطلوب',
      'invalidEmail': 'أدخل بريدًا إلكترونيًا صالحًا',
      'invalidNumber': 'أدخل رقمًا صالحًا',
      'invalidOption': 'اختر أحد الخيارات',
      'selectAnOption': 'اختر…',
      'somethingWentWrong': 'حدث خطأ ما. حاول مرة أخرى.',
      'retry': 'إعادة المحاولة',
      'couldNotConnect': 'تعذّر الاتصال. تحقق من اتصالك وحاول مرة أخرى.',
      'rateYourChat': 'قيّم محادثتك',
      'rateHint': 'كيف كانت محادثتك؟',
      'addAComment': 'أضف تعليقًا (اختياري)',
      'submit': 'إرسال',
      'thanksForFeedback': 'شكرًا على ملاحظاتك!',
      'yourName': 'اسمك',
      'yourEmail': 'بريدك الإلكتروني',
      'yourMessage': 'رسالتك',
      'sendMessage': 'إرسال الرسالة',
      'closedNotice': 'فريقنا غير متاح حالياً. اترك رسالتك وسنرد عليك فور عودتنا.',
      'backAt': 'نعود الساعة {time}.',
      'noAgentsNotice': 'الجميع مشغول حالياً. اترك رسالة وسنرد قريباً.',
      'closedForLabel': 'نحن مغلقون بمناسبة {label}.',
      'unavailableTitle': 'غير متاحين حالياً',
      'offlineThanks': 'شكرًا! سنعاود التواصل معك.',
      'exitChatTitle': 'هل تريد حقًا إغلاق هذه الدردشة؟',
      'exitChatConfirm': 'إغلاق الدردشة',
      'exitChatCancel': 'إلغاء',
    },
    'ckb': {
      'send': 'ناردن',
      'typeAMessage': 'پەیامێک بنووسە',
      'attach': 'هاوپێچکردن',
      'attachImage': 'وێنە',
      'attachFile': 'پەڕگە',
      'agentTyping': 'دەنووسێت…',
      'loadOlder': 'پەیامە کۆنەکان باربکە',
      'mediaUnavailable': 'مێدیا بەردەست نییە',
      'download': 'داگرتن',
      'image': 'وێنە',
      'attachment': 'هاوپێچ',
      'sendFailedRetry': 'نەنێردرا. بۆ دووبارەکردنەوە دەستبنێ.',
      'sending': 'دەنێردرێت…',
      'startChat': 'دەستپێکردنی گفتوگۆ',
      'fieldRequired': 'ئەم خانەیە پێویستە',
      'invalidEmail': 'ئیمەیڵێکی دروست بنووسە',
      'invalidNumber': 'ژمارەیەکی دروست بنووسە',
      'invalidOption': 'یەکێک لە هەڵبژاردەکان هەڵبژێرە',
      'selectAnOption': 'هەڵبژێرە…',
      'somethingWentWrong': 'هەڵەیەک ڕوویدا. تکایە دووبارە هەوڵبدەرەوە.',
      'retry': 'دووبارە هەوڵبدەرەوە',
      'couldNotConnect': 'پەیوەندی نەکرا. لە پەیوەندیەکەت بڕوانە و دووبارە هەوڵبدەرەوە.',
      'rateYourChat': 'گفتوگۆکەت هەڵبسەنگێنە',
      'rateHint': 'گفتوگۆکەت چۆن بوو؟',
      'addAComment': 'لێدوانێک زیاد بکە (ئارەزوومەندانە)',
      'submit': 'ناردن',
      'thanksForFeedback': 'سوپاس بۆ ڕاتەکانت!',
      'yourName': 'ناوت',
      'yourEmail': 'ئیمەیڵەکەت',
      'yourMessage': 'پەیامەکەت',
      'sendMessage': 'ناردنی پەیام',
      'closedNotice': 'تیمەکەمان ئێستا دەرەوەی کارە. نامەکەت بەجێبهێڵە، هەرکە گەڕاینەوە وەڵامت دەدەینەوە.',
      'backAt': 'لە {time} دەگەڕێینەوە.',
      'noAgentsNotice': 'ئێستا هەموو خەریکن. نامەیەک بەجێبهێڵە، بەم زووانە وەڵامت دەدەینەوە.',
      'closedForLabel': 'بەهۆی {label} داخراوین.',
      'unavailableTitle': 'ئێستا بەردەست نین',
      'offlineThanks': 'سوپاس! بەمزووانە پەیوەندیت پێوە دەکەین.',
      'exitChatTitle': 'بەڕاستی دەتەوێت ئەم گفتوگۆیە دابخەیت؟',
      'exitChatConfirm': 'داخستنی گفتوگۆ',
      'exitChatCancel': 'پاشگەزبوونەوە',
    },
    'de': {
      'send': 'Senden',
      'typeAMessage': 'Nachricht schreiben',
      'attach': 'Anhängen',
      'attachImage': 'Foto',
      'attachFile': 'Datei',
      'agentTyping': 'Schreibt…',
      'loadOlder': 'Ältere Nachrichten laden',
      'mediaUnavailable': 'Medium nicht verfügbar',
      'download': 'Herunterladen',
      'image': 'Bild',
      'attachment': 'Anhang',
      'sendFailedRetry': 'Nicht gesendet. Zum Wiederholen tippen.',
      'sending': 'Senden…',
      'startChat': 'Chat starten',
      'fieldRequired': 'Dieses Feld ist erforderlich',
      'invalidEmail': 'Gültige E-Mail-Adresse eingeben',
      'invalidNumber': 'Gültige Zahl eingeben',
      'invalidOption': 'Eine der Optionen wählen',
      'selectAnOption': 'Auswählen…',
      'somethingWentWrong': 'Etwas ist schiefgelaufen. Bitte erneut versuchen.',
      'rateYourChat': 'Chat bewerten',
      'rateHint': 'Wie war Ihr Gespräch?',
      'addAComment': 'Kommentar hinzufügen (optional)',
      'submit': 'Absenden',
      'thanksForFeedback': 'Danke für Ihr Feedback!',
      'yourName': 'Ihr Name',
      'yourEmail': 'Ihre E-Mail',
      'yourMessage': 'Ihre Nachricht',
      'sendMessage': 'Nachricht senden',
      'closedNotice': 'Unser Team ist gerade offline. Hinterlassen Sie Ihre Nachricht — wir antworten, sobald wir zurück sind.',
      'backAt': 'Wir sind ab {time} wieder da.',
      'noAgentsNotice': 'Gerade sind alle beschäftigt. Hinterlassen Sie eine Nachricht — wir melden uns gleich.',
      'closedForLabel': 'Wir haben wegen {label} geschlossen.',
      'unavailableTitle': 'Wir sind gerade nicht erreichbar',
      'offlineThanks': 'Danke! Wir melden uns bei Ihnen.',
      'exitChatTitle': 'Möchten Sie diesen Chat wirklich schließen?',
      'exitChatConfirm': 'Chat schließen',
      'exitChatCancel': 'Abbrechen',
    },
    'es': {
      'send': 'Enviar',
      'typeAMessage': 'Escribe un mensaje',
      'attach': 'Adjuntar',
      'attachImage': 'Foto',
      'attachFile': 'Archivo',
      'agentTyping': 'Escribiendo…',
      'loadOlder': 'Cargar mensajes anteriores',
      'mediaUnavailable': 'Contenido no disponible',
      'download': 'Descargar',
      'image': 'Imagen',
      'attachment': 'Adjunto',
      'sendFailedRetry': 'No enviado. Toca para reintentar.',
      'sending': 'Enviando…',
      'startChat': 'Iniciar chat',
      'fieldRequired': 'Este campo es obligatorio',
      'invalidEmail': 'Introduce un correo válido',
      'invalidNumber': 'Introduce un número válido',
      'invalidOption': 'Elige una de las opciones',
      'selectAnOption': 'Selecciona…',
      'somethingWentWrong': 'Algo salió mal. Inténtalo de nuevo.',
      'rateYourChat': 'Valora tu chat',
      'rateHint': '¿Qué tal fue tu conversación?',
      'addAComment': 'Añade un comentario (opcional)',
      'submit': 'Enviar',
      'thanksForFeedback': '¡Gracias por tu opinión!',
      'yourName': 'Tu nombre',
      'yourEmail': 'Tu correo',
      'yourMessage': 'Tu mensaje',
      'sendMessage': 'Enviar mensaje',
      'closedNotice': 'Nuestro equipo no está disponible ahora. Deja tu mensaje y te responderemos en cuanto volvamos.',
      'backAt': 'Volvemos a las {time}.',
      'noAgentsNotice': 'Ahora mismo todos están ocupados. Deja un mensaje y te responderemos en breve.',
      'closedForLabel': 'Cerramos por {label}.',
      'unavailableTitle': 'No estamos disponibles ahora',
      'offlineThanks': '¡Gracias! Te responderemos pronto.',
      'exitChatTitle': '¿Seguro que quieres cerrar este chat?',
      'exitChatConfirm': 'Cerrar chat',
      'exitChatCancel': 'Cancelar',
    },
    'fr': {
      'send': 'Envoyer',
      'typeAMessage': 'Écrivez un message',
      'attach': 'Joindre',
      'attachImage': 'Photo',
      'attachFile': 'Fichier',
      'agentTyping': 'En train d’écrire…',
      'loadOlder': 'Charger les messages précédents',
      'mediaUnavailable': 'Média indisponible',
      'download': 'Télécharger',
      'image': 'Image',
      'attachment': 'Pièce jointe',
      'sendFailedRetry': 'Non envoyé. Touchez pour réessayer.',
      'sending': 'Envoi…',
      'startChat': 'Démarrer le chat',
      'fieldRequired': 'Ce champ est obligatoire',
      'invalidEmail': 'Saisissez une adresse e-mail valide',
      'invalidNumber': 'Saisissez un nombre valide',
      'invalidOption': 'Choisissez l’une des options',
      'selectAnOption': 'Sélectionner…',
      'somethingWentWrong': 'Une erreur est survenue. Réessayez.',
      'rateYourChat': 'Évaluez votre chat',
      'rateHint': 'Comment s’est passée votre conversation ?',
      'addAComment': 'Ajoutez un commentaire (facultatif)',
      'submit': 'Envoyer',
      'thanksForFeedback': 'Merci pour votre retour !',
      'yourName': 'Votre nom',
      'yourEmail': 'Votre e-mail',
      'yourMessage': 'Votre message',
      'sendMessage': 'Envoyer le message',
      'closedNotice': 'Notre équipe est hors ligne pour le moment. Laissez votre message, nous répondrons dès notre retour.',
      'backAt': 'Nous revenons à {time}.',
      'noAgentsNotice': "Tout le monde est occupé pour l'instant. Laissez un message, nous répondrons vite.",
      'closedForLabel': 'Nous sommes fermés pour {label}.',
      'unavailableTitle': 'Nous ne sommes pas disponibles pour le moment',
      'offlineThanks': 'Merci ! Nous reviendrons vers vous.',
      'exitChatTitle': 'Voulez-vous vraiment fermer cette discussion ?',
      'exitChatConfirm': 'Fermer la discussion',
      'exitChatCancel': 'Annuler',
    },
    'hi': {
      'send': 'भेजें',
      'typeAMessage': 'संदेश लिखें',
      'attach': 'संलग्न करें',
      'attachImage': 'फ़ोटो',
      'attachFile': 'फ़ाइल',
      'agentTyping': 'टाइप कर रहे हैं…',
      'loadOlder': 'पुराने संदेश लोड करें',
      'mediaUnavailable': 'मीडिया उपलब्ध नहीं है',
      'download': 'डाउनलोड',
      'image': 'छवि',
      'attachment': 'अनुलग्नक',
      'sendFailedRetry': 'भेजा नहीं गया। पुनः प्रयास के लिए टैप करें।',
      'sending': 'भेजा जा रहा है…',
      'startChat': 'चैट शुरू करें',
      'fieldRequired': 'यह फ़ील्ड आवश्यक है',
      'invalidEmail': 'मान्य ईमेल पता दर्ज करें',
      'invalidNumber': 'मान्य संख्या दर्ज करें',
      'invalidOption': 'किसी एक विकल्प को चुनें',
      'selectAnOption': 'चुनें…',
      'somethingWentWrong': 'कुछ गड़बड़ हो गई। कृपया पुनः प्रयास करें।',
      'rateYourChat': 'अपनी चैट को रेट करें',
      'rateHint': 'आपकी बातचीत कैसी रही?',
      'addAComment': 'टिप्पणी जोड़ें (वैकल्पिक)',
      'submit': 'सबमिट करें',
      'thanksForFeedback': 'आपकी प्रतिक्रिया के लिए धन्यवाद!',
      'yourName': 'आपका नाम',
      'yourEmail': 'आपका ईमेल',
      'yourMessage': 'आपका संदेश',
      'sendMessage': 'संदेश भेजें',
      'closedNotice': 'हमारी टीम अभी ऑफ़लाइन है। अपना संदेश छोड़ें, लौटते ही हम उत्तर देंगे।',
      'backAt': 'हम {time} बजे लौटते हैं।',
      'noAgentsNotice': 'अभी सभी व्यस्त हैं। संदेश छोड़ें, हम जल्द उत्तर देंगे।',
      'closedForLabel': 'हम {label} के कारण बंद हैं।',
      'unavailableTitle': 'हम अभी उपलब्ध नहीं हैं',
      'offlineThanks': 'धन्यवाद! हम आपसे जल्द संपर्क करेंगे।',
      'exitChatTitle': 'क्या आप वाकई यह चैट बंद करना चाहते हैं?',
      'exitChatConfirm': 'चैट बंद करें',
      'exitChatCancel': 'रद्द करें',
    },
    'it': {
      'send': 'Invia',
      'typeAMessage': 'Scrivi un messaggio',
      'attach': 'Allega',
      'attachImage': 'Foto',
      'attachFile': 'File',
      'agentTyping': 'Sta scrivendo…',
      'loadOlder': 'Carica messaggi precedenti',
      'mediaUnavailable': 'Contenuto non disponibile',
      'download': 'Scarica',
      'image': 'Immagine',
      'attachment': 'Allegato',
      'sendFailedRetry': 'Non inviato. Tocca per riprovare.',
      'sending': 'Invio…',
      'startChat': 'Avvia chat',
      'fieldRequired': 'Questo campo è obbligatorio',
      'invalidEmail': 'Inserisci un’email valida',
      'invalidNumber': 'Inserisci un numero valido',
      'invalidOption': 'Scegli una delle opzioni',
      'selectAnOption': 'Seleziona…',
      'somethingWentWrong': 'Qualcosa è andato storto. Riprova.',
      'rateYourChat': 'Valuta la tua chat',
      'rateHint': 'Com’è andata la conversazione?',
      'addAComment': 'Aggiungi un commento (facoltativo)',
      'submit': 'Invia',
      'thanksForFeedback': 'Grazie per il tuo feedback!',
      'yourName': 'Il tuo nome',
      'yourEmail': 'La tua email',
      'yourMessage': 'Il tuo messaggio',
      'sendMessage': 'Invia messaggio',
      'closedNotice': 'Il nostro team non è disponibile al momento. Lascia il tuo messaggio e ti risponderemo appena torniamo.',
      'backAt': 'Torniamo alle {time}.',
      'noAgentsNotice': 'Al momento sono tutti occupati. Lascia un messaggio e ti risponderemo a breve.',
      'closedForLabel': 'Siamo chiusi per {label}.',
      'unavailableTitle': 'Al momento non siamo disponibili',
      'offlineThanks': 'Grazie! Ti risponderemo presto.',
      'exitChatTitle': 'Vuoi davvero chiudere questa chat?',
      'exitChatConfirm': 'Chiudi chat',
      'exitChatCancel': 'Annulla',
    },
    'kmr': {
      'send': 'فرێکرن',
      'typeAMessage': 'نامەکێ بنڤیسە',
      'attach': 'هەڤپێچکرن',
      'attachImage': 'وێنە',
      'attachFile': 'پەل',
      'agentTyping': 'د نڤیسینێ دا…',
      'loadOlder': 'نامەێن کەڤن باربکە',
      'mediaUnavailable': 'مێدیا بەردەست نینە',
      'download': 'داگرتن',
      'image': 'وێنە',
      'attachment': 'هەڤپێچ',
      'sendFailedRetry': 'نەهاتە فرێکرن. بۆ دووبارە هەوڵدانێ بکرتە بکە.',
      'sending': 'د هنێریت…',
      'startChat': 'دەستپێکرنا چاتێ',
      'fieldRequired': 'ئەڤ خانە پێدڤی یە',
      'invalidEmail': 'ئیمەیلەکا دروست بنڤیسە',
      'invalidNumber': 'ژمارەکا دروست بنڤیسە',
      'invalidOption': 'یەکێ ژ هەلبژارتنان هەلبژێرە',
      'selectAnOption': 'هەلبژێرە…',
      'somethingWentWrong': 'چەوتیەک چێبوو. ژکەرەمێ دووبارە هەوڵ بدە.',
      'retry': 'دووبارە هەوڵدان',
      'couldNotConnect': 'پەیوەندی نەهاتە کرن. پەیوەندیا خۆ ببینە و دووبارە هەوڵ بدە.',
      'rateYourChat': 'چاتا خۆ هەلسەنگێنە',
      'rateHint': 'ئاخڤتنا تە چاوا بوو؟',
      'addAComment': 'تێبینیەکێ زێدە بکە (هەلبژارتی)',
      'submit': 'پێشکێش بکە',
      'thanksForFeedback': 'سوپاس بۆ بۆچوونا تە!',
      'yourName': 'ناڤێ تە',
      'yourEmail': 'ئیمەیلا تە',
      'yourMessage': 'نامەیا تە',
      'sendMessage': 'نامەیێ فرێکە',
      'closedNotice': 'تیمێ مە نوکە نە ل سەر خەتێ یە. پەیاما خۆ بهێلە، گاڤا ئەم ڤەگەڕین دێ بەرسڤا تە دەین.',
      'backAt': 'ئەم د {time} دا ڤەدگەڕین.',
      'noAgentsNotice': 'نوکە هەمی مژویل ن. پەیامەکێ بهێلە، دێ زوی بەرسڤ دەین.',
      'closedForLabel': 'ئەم ژ بەر {label} گرتی ن.',
      'unavailableTitle': 'ئەم نوکە بەردەست نینن',
      'offlineThanks': 'سوپاس! ئەم دێ ب تە ڤە پەیوەندیێ کەین.',
      'exitChatTitle': 'ب ڕاستی دڤێت ڤێ چاتێ بگری؟',
      'exitChatConfirm': 'چاتێ بگرە',
      'exitChatCancel': 'بەتالکرن',
    },
    'pt': {
      'send': 'Enviar',
      'typeAMessage': 'Escreva uma mensagem',
      'attach': 'Anexar',
      'attachImage': 'Foto',
      'attachFile': 'Arquivo',
      'agentTyping': 'Digitando…',
      'loadOlder': 'Carregar mensagens anteriores',
      'mediaUnavailable': 'Mídia indisponível',
      'download': 'Baixar',
      'image': 'Imagem',
      'attachment': 'Anexo',
      'sendFailedRetry': 'Não enviado. Toque para tentar de novo.',
      'sending': 'Enviando…',
      'startChat': 'Iniciar conversa',
      'fieldRequired': 'Este campo é obrigatório',
      'invalidEmail': 'Insira um e-mail válido',
      'invalidNumber': 'Insira um número válido',
      'invalidOption': 'Escolha uma das opções',
      'selectAnOption': 'Selecionar…',
      'somethingWentWrong': 'Algo deu errado. Tente novamente.',
      'rateYourChat': 'Avalie sua conversa',
      'rateHint': 'Como foi sua conversa?',
      'addAComment': 'Adicione um comentário (opcional)',
      'submit': 'Enviar',
      'thanksForFeedback': 'Obrigado pelo seu feedback!',
      'yourName': 'Seu nome',
      'yourEmail': 'Seu e-mail',
      'yourMessage': 'Sua mensagem',
      'sendMessage': 'Enviar mensagem',
      'closedNotice': 'A nossa equipa está offline neste momento. Deixe a sua mensagem e responderemos assim que voltarmos.',
      'backAt': 'Voltamos às {time}.',
      'noAgentsNotice': 'Estamos todos ocupados neste momento. Deixe uma mensagem e responderemos em breve.',
      'closedForLabel': 'Estamos fechados por {label}.',
      'unavailableTitle': 'Não estamos disponíveis no momento',
      'offlineThanks': 'Obrigado! Entraremos em contato.',
      'exitChatTitle': 'Tem certeza de que deseja fechar esta conversa?',
      'exitChatConfirm': 'Fechar conversa',
      'exitChatCancel': 'Cancelar',
    },
    'tr': {
      'send': 'Gönder',
      'typeAMessage': 'Bir mesaj yazın',
      'attach': 'Ekle',
      'attachImage': 'Fotoğraf',
      'attachFile': 'Dosya',
      'agentTyping': 'Yazıyor…',
      'loadOlder': 'Önceki mesajları yükle',
      'mediaUnavailable': 'Medya kullanılamıyor',
      'download': 'İndir',
      'image': 'Görsel',
      'attachment': 'Ek',
      'sendFailedRetry': 'Gönderilmedi. Yeniden denemek için dokunun.',
      'sending': 'Gönderiliyor…',
      'startChat': 'Sohbeti başlat',
      'fieldRequired': 'Bu alan zorunludur',
      'invalidEmail': 'Geçerli bir e-posta girin',
      'invalidNumber': 'Geçerli bir sayı girin',
      'invalidOption': 'Seçeneklerden birini seçin',
      'selectAnOption': 'Seçin…',
      'somethingWentWrong': 'Bir şeyler ters gitti. Tekrar deneyin.',
      'rateYourChat': 'Sohbetinizi değerlendirin',
      'rateHint': 'Görüşmeniz nasıldı?',
      'addAComment': 'Yorum ekleyin (isteğe bağlı)',
      'submit': 'Gönder',
      'thanksForFeedback': 'Geri bildiriminiz için teşekkürler!',
      'yourName': 'Adınız',
      'yourEmail': 'E-postanız',
      'yourMessage': 'Mesajınız',
      'sendMessage': 'Mesaj gönder',
      'closedNotice': 'Ekibimiz şu anda çevrimdışı. Mesajınızı bırakın, döndüğümüzde hemen yanıtlayalım.',
      'backAt': '{time} itibarıyla döneriz.',
      'noAgentsNotice': 'Şu anda herkes meşgul. Mesaj bırakın, kısa sürede dönelim.',
      'closedForLabel': '{label} nedeniyle kapalıyız.',
      'unavailableTitle': 'Şu anda müsait değiliz',
      'offlineThanks': 'Teşekkürler! Size geri döneceğiz.',
      'exitChatTitle': 'Bu sohbeti kapatmak istediğinize emin misiniz?',
      'exitChatConfirm': 'Sohbeti kapat',
      'exitChatCancel': 'İptal',
    },
    'ur': {
      'send': 'بھیجیں',
      'typeAMessage': 'پیغام لکھیں',
      'attach': 'منسلک کریں',
      'attachImage': 'تصویر',
      'attachFile': 'فائل',
      'agentTyping': 'لکھ رہے ہیں…',
      'loadOlder': 'پرانے پیغامات لوڈ کریں',
      'mediaUnavailable': 'میڈیا دستیاب نہیں',
      'download': 'ڈاؤن لوڈ',
      'image': 'تصویر',
      'attachment': 'منسلکہ',
      'sendFailedRetry': 'نہیں بھیجا گیا۔ دوبارہ کوشش کے لیے ٹیپ کریں۔',
      'sending': 'بھیجا جا رہا ہے…',
      'startChat': 'چیٹ شروع کریں',
      'fieldRequired': 'یہ خانہ ضروری ہے',
      'invalidEmail': 'درست ای میل درج کریں',
      'invalidNumber': 'درست نمبر درج کریں',
      'invalidOption': 'کسی ایک آپشن کا انتخاب کریں',
      'selectAnOption': 'منتخب کریں…',
      'somethingWentWrong': 'کچھ غلط ہو گیا۔ دوبارہ کوشش کریں۔',
      'rateYourChat': 'اپنی چیٹ کو ریٹ کریں',
      'rateHint': 'آپ کی گفتگو کیسی رہی؟',
      'addAComment': 'تبصرہ شامل کریں (اختیاری)',
      'submit': 'جمع کرائیں',
      'thanksForFeedback': 'آپ کی رائے کا شکریہ!',
      'yourName': 'آپ کا نام',
      'yourEmail': 'آپ کا ای میل',
      'yourMessage': 'آپ کا پیغام',
      'sendMessage': 'پیغام بھیجیں',
      'closedNotice': 'ہماری ٹیم اس وقت آف لائن ہے۔ اپنا پیغام چھوڑ دیں، واپس آتے ہی جواب دیں گے۔',
      'backAt': 'ہم {time} بجے واپس آتے ہیں۔',
      'noAgentsNotice': 'اس وقت سب مصروف ہیں۔ پیغام چھوڑیں، ہم جلد جواب دیں گے۔',
      'closedForLabel': 'ہم {label} کی وجہ سے بند ہیں۔',
      'unavailableTitle': 'ہم اس وقت دستیاب نہیں ہیں',
      'offlineThanks': 'شکریہ! ہم جلد آپ سے رابطہ کریں گے۔',
      'exitChatTitle': 'کیا آپ واقعی یہ چیٹ بند کرنا چاہتے ہیں؟',
      'exitChatConfirm': 'چیٹ بند کریں',
      'exitChatCancel': 'منسوخ کریں',
    },
    'zh': {
      'send': '发送',
      'typeAMessage': '输入消息',
      'attach': '附件',
      'attachImage': '照片',
      'attachFile': '文件',
      'agentTyping': '正在输入…',
      'loadOlder': '加载更早的消息',
      'mediaUnavailable': '媒体不可用',
      'download': '下载',
      'image': '图片',
      'attachment': '附件',
      'sendFailedRetry': '未发送。点按重试。',
      'sending': '发送中…',
      'startChat': '开始聊天',
      'fieldRequired': '此字段为必填项',
      'invalidEmail': '请输入有效的电子邮箱',
      'invalidNumber': '请输入有效的数字',
      'invalidOption': '请选择其中一个选项',
      'selectAnOption': '请选择…',
      'somethingWentWrong': '出错了，请重试。',
      'rateYourChat': '为您的聊天评分',
      'rateHint': '您的对话体验如何？',
      'addAComment': '添加评论（可选）',
      'submit': '提交',
      'thanksForFeedback': '感谢您的反馈！',
      'yourName': '您的姓名',
      'yourEmail': '您的邮箱',
      'yourMessage': '您的留言',
      'sendMessage': '发送留言',
      'closedNotice': '我们的团队当前不在线。请留言，我们回来后会尽快回复。',
      'backAt': '我们将于 {time} 回来。',
      'noAgentsNotice': '目前大家都在忙。请留言，我们会尽快回复。',
      'closedForLabel': '我们因{label}休息。',
      'unavailableTitle': '我们现在无法接待',
      'offlineThanks': '谢谢！我们会尽快回复您。',
      'exitChatTitle': '确定要关闭此对话吗？',
      'exitChatConfirm': '关闭对话',
      'exitChatCancel': '取消',
    },
  };
}
