import Foundation

/// Constants and prompts, ported verbatim from pdf_namer.py (ParityTests checks the prompts).
public enum Config {
    public static let maxPages = 5
    public static let maxChars = 5000  // the model's context is 8192 tokens: rules + text + page image must fit
    public static let imageDPI: CGFloat = 110
    public static let ocrDPI: CGFloat = 144
    public static let imageMaxPx = 1600
    public static let pdfExts: Set<String> = ["pdf"]
    public static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff"]
    public static let backupPrefix = "RENAME BACKUP"

    public static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return pdfExts.contains(ext) || imageExts.contains(ext)
    }

    public static func isImage(_ url: URL) -> Bool { imageExts.contains(url.pathExtension.lowercased()) }

    static let intro = """
        Tu nommes des fichiers de documents (personnels et professionnels) à partir de leur \
        contenu. On te donne le texte du document et l'image de sa première page. \
        Remplis chaque champ en suivant ces règles.


        """

    static let rules = """
        type = choisis dans cette liste (sinon 1 à 3 mots):
        - Facture: demande de paiement d'un fournisseur, prestataire ou professionnel \
        (y compris facture acquittée, note d'honoraires, titre de recette d'hôpital).
        - Reçu de paiement: confirmation de paiement en ligne, par carte, ticket de caisse.
        - Avoir, Devis, Bon de commande, Note de frais (frais professionnels remboursés \
        par un employeur), Quittance (loyer).
        - Relevé de compte: relevé bancaire ou de carte. Relevé de prestations: \
        remboursements de mutuelle ou d'assurance maladie. Échéancier.
        - Avis d'imposition: impôt ou taxe à payer (impôt sur le revenu, CFE, taxe foncière). \
        Déclaration: déclaration fiscale ou sociale (DSN, TVA, revenus).
        - Récépissé: accusé de réception ou confirmation d'une démarche auprès d'une administration.
        - Attestation, Certificat, Contrat, Avenant, Conditions générales, Procès-verbal \
        (assemblée générale), Bilan (comptes annuels), Rapport.
        - Bulletin de paie, Bulletin scolaire, Convocation.
        - Ordonnance: prescription d'un médecin (médicaments, vaccins, examens). \
        Compte rendu: compte rendu médical, résultats d'examen ou de réunion.
        - Lettre: courrier ou e-mail. Billet: transport, spectacle, réservation. Notice: mode d'emploi.

        issuer = qui a ÉCRIT le document (en-tête, logo, signature). JAMAIS le destinataire, \
        le client ou le patient. Forme courte et lisible:
        - entreprise ou marque: son nom sans forme juridique (SAS, SARL...).
        - administration: nom usuel (Finances publiques, URSSAF, CPAM, CAF, Mairie de Lyon).
        - hôpital ou clinique: son nom (Hôpital Necker).
        - médecin, professionnel de santé ou libéral: métier + nom de famille \
        (Dr Martin, Kiné Durand, Orthodontiste Lefèvre, Avocat Moreau).
        - déclaration: celui qui déclare (l'entreprise ou la personne), pas l'organisme destinataire.
        - aucun si pas clair.

        date = date d'émission du document (date de la facture, de l'ordonnance, du courrier, \
        de l'avis). JAMAIS une date de naissance, une date limite ou d'échéance, ni une période. \
        aucun si absente.

        detail = 2 à 6 mots sur l'objet précis: produit ou service acheté, médicament, \
        période d'un relevé (Octobre 2026), objet d'un courrier ou d'un contrat. \
        Ne répète pas le type ni l'émetteur. JAMAIS de numéro de facture, \
        de dossier ou de référence.

        amount = pour factures, reçus, devis, avoirs, quittances, notes de frais: \
        montant total TTC payé ou à payer, point décimal, code devise ISO (EUR, USD, GBP, CHF). \
        aucun pour les autres documents.

        Écris en casse normale (majuscule aux noms propres), JAMAIS tout en majuscules, même si le document est en majuscules. Garde les sigles (URSSAF, CFE, IRM).
        Utilise uniquement des faits présents dans le document.

        Exemples:
        type: Facture
        issuer: Kiné Durand
        date: 2025-03-14
        detail: Séances de rééducation genou
        amount: 180.00 EUR

        type: Avis d'imposition
        issuer: Finances publiques
        date: 2025-08-29
        detail: Impôt sur le revenu 2024
        amount: aucun

        type: Contrat
        issuer: Free
        date: 2024-11-02
        detail: Abonnement fibre Freebox Pop
        amount: aucun
        """

    public static let instructions = intro + rules

    public static let imageInstructions = intro.replacingOccurrences(
        of: "l'image de sa première page", with: "l'image") + """
        Si l'image n'est PAS un document papier ou PDF:
        - photo (lieu, objet, personne, affiche): type = Photo, issuer = aucun, \
        date = aucun, amount = aucun, detail = le sujet en 3 à 8 mots avec les noms ou titres visibles.
        - capture d'écran d'une app, d'un site ou d'un e-mail (même s'il parle d'une commande, \
        d'un retour, d'un rendez-vous ou d'un paiement): type = Capture écran, \
        issuer = le site, l'app ou l'expéditeur (Amazon, Doctolib, SNCF...), \
        date = aucun, amount = aucun, detail = l'action et le produit ou sujet principal \
        en 3 à 8 mots (ex: Retour aspirateur Dyson V8).
        Si l'image montre un vrai document (facture, ticket, reçu, courrier, ordonnance...):

        """ + rules

    public static let types = [
        "Facture", "Reçu de paiement", "Avoir", "Devis", "Bon de commande", "Note de frais",
        "Quittance", "Relevé de compte", "Relevé de prestations", "Échéancier",
        "Avis d'imposition", "Déclaration", "Récépissé", "Attestation", "Certificat", "Contrat",
        "Avenant", "Conditions générales", "Procès-verbal", "Bilan", "Rapport", "Bulletin de paie",
        "Bulletin scolaire", "Convocation", "Ordonnance", "Compte rendu", "Lettre", "Billet",
        "Notice", "Décision",
    ]
    public static let imageTypes = types + ["Photo", "Capture écran"]
}
