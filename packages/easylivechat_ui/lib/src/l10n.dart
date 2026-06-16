import 'dart:ui' show PlatformDispatcher;

/// SDK "chrome" strings for the prebuilt UI (`Send`, `Rate your chat`, …).
///
/// These are the framework's own labels — distinct from tenant-authored copy
/// (`welcomeTitle`, pre-chat field labels, `offlineMessage`) which is rendered
/// **verbatim** and never localized. We ship all 12 product locales to match
/// the dashboard (`ar de en es fr hi it ku pt tr ur zh`) and fall back to
/// English for any missing key/locale — never hardcode English at the call
/// site (project i18n rule).
///
/// Resolution: an explicit locale (from `EasyLiveChatConfig.locale` /
/// `WidgetConfig.locale`) wins; otherwise the platform locale; otherwise `en`.
/// Matching is by the language subtag only (e.g. `pt-BR` → `pt`).
class ElcStrings {
  final String _lang;
  const ElcStrings._(this._lang);

  /// Resolve strings for [localeCode] (e.g. `en`, `ar`, `pt-BR`). Null/unknown
  /// falls back to the device locale, then English.
  factory ElcStrings.of(String? localeCode) {
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
    // Kurdish: ckb (Central Kurdish / Sorani) maps to the existing `ku` table;
    // kmr (Northern Kurdish / Kurmanji / Badini) has its own table below.
    if (lang == 'ckb') return 'ku';
    return lang;
  }

  String _t(String key) {
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
      'couldNotConnect':
          "Couldn't connect. Check your connection and try again.",
      'rateYourChat': 'Rate your chat',
      'rateHint': 'How was your conversation?',
      'addAComment': 'Add a comment (optional)',
      'submit': 'Submit',
      'thanksForFeedback': 'Thanks for your feedback!',
      'yourName': 'Your name',
      'yourEmail': 'Your email',
      'yourMessage': 'Your message',
      'sendMessage': 'Send message',
      'offlineThanks': "Thanks! We'll get back to you.",
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
      'offlineThanks': 'شكرًا! سنعاود التواصل معك.',
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
      'offlineThanks': 'Danke! Wir melden uns bei Ihnen.',
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
      'offlineThanks': '¡Gracias! Te responderemos pronto.',
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
      'offlineThanks': 'Merci ! Nous reviendrons vers vous.',
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
      'offlineThanks': 'धन्यवाद! हम आपसे जल्द संपर्क करेंगे।',
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
      'offlineThanks': 'Grazie! Ti risponderemo presto.',
    },
    'ku': {
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
      'couldNotConnect':
          'پەیوەندی نەکرا. لە پەیوەندیەکەت بڕوانە و دووبارە هەوڵبدەرەوە.',
      'rateYourChat': 'گفتوگۆکەت هەڵبسەنگێنە',
      'rateHint': 'گفتوگۆکەت چۆن بوو؟',
      'addAComment': 'لێدوانێک زیاد بکە (ئارەزوومەندانە)',
      'submit': 'ناردن',
      'thanksForFeedback': 'سوپاس بۆ ڕاتەکانت!',
      'yourName': 'ناوت',
      'yourEmail': 'ئیمەیڵەکەت',
      'yourMessage': 'پەیامەکەت',
      'sendMessage': 'ناردنی پەیام',
      'offlineThanks': 'سوپاس! بەمزووانە پەیوەندیت پێوە دەکەین.',
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
      'offlineThanks': 'Obrigado! Entraremos em contato.',
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
      'offlineThanks': 'Teşekkürler! Size geri döneceğiz.',
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
      'offlineThanks': 'شکریہ! ہم جلد آپ سے رابطہ کریں گے۔',
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
      'offlineThanks': '谢谢！我们会尽快回复您。',
    },
    // Northern Kurdish (Kurmanji / Badini, Arabic script). Zirak's default
    // locale; ckb (Sorani) maps to `ku` above. Core terms verified against the
    // Zirak apps' own kmr translations.
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
      'couldNotConnect':
          'پەیوەندی نەهاتە کرن. پەیوەندیا خۆ ببینە و دووبارە هەوڵ بدە.',
      'rateYourChat': 'چاتا خۆ هەلسەنگێنە',
      'rateHint': 'ئاخڤتنا تە چاوا بوو؟',
      'addAComment': 'تێبینیەکێ زێدە بکە (هەلبژارتی)',
      'submit': 'پێشکێش بکە',
      'thanksForFeedback': 'سوپاس بۆ بۆچوونا تە!',
      'yourName': 'ناڤێ تە',
      'yourEmail': 'ئیمەیلا تە',
      'yourMessage': 'نامەیا تە',
      'sendMessage': 'نامەیێ فرێکە',
      'offlineThanks': 'سوپاس! ئەم دێ ب تە ڤە پەیوەندیێ کەین.',
    },
  };
}
