"""Generate Tests/PDFNamerCoreTests/Fixtures/parity.json from the Python reference.

Imports ~/bin/pdf_namer.py and records what its naming rules return on a large,
seeded set of inputs; ParityTests.swift checks the Swift port returns the same.

    uv run --python 3.13 --with rich python tools/gen_parity.py [path/to/pdf_namer.py]
"""

import datetime, importlib.util, json, os, random, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/bin/pdf_namer.py")
TODAY = datetime.date(2026, 11, 9)

spec = importlib.util.spec_from_file_location("pdf_namer", SRC)
pn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pn)


class FakeDate(datetime.date):
    @classmethod
    def today(cls):
        return cls(TODAY.year, TODAY.month, TODAY.day)


class FakeDatetime:
    date = FakeDate
    timedelta = datetime.timedelta
    datetime = datetime.datetime


pn.datetime = FakeDatetime  # pin "today" so the fixture never goes stale

rng = random.Random(42)

TYPES = pn.IMAGE_TYPES + ["FACTURE", "Photo ou Capture écran", "facture proforma", "aucun", "", "Relevé De Compte",
                          "CONTRAT D'ENTRETIEN", "Note d'honoraires", "RECU", "Invoice", "Ticket de caisse",
                          "Courrier", "N/A", "Avis D'ÉCHÉANCE", "Vorauszahlungsrechnung"]
ISSUERS = ["EDF", "PIXEL UP STUDIO", "Docteur Martin", "dr. DUPONT", "Dr Martin", "Finances publiques", "URSSAF",
           "ORANGE", "orange", "NEOVision", "Kiné Durand", "SAS LE PETIT CAFÉ", "Free", "AP-HP", "Le Petit Café",
           "Hôpital Necker-Enfants Malades", "aucun", "", "N/A", "Mairie de Lyon / Service état civil", "Amazon.fr",
           "L'ÉQUIPE", "Julie", "Société Générale", "M. JEAN-PIERRE DE LA FONTAINE", "CPAM DU RHÔNE", "edf",
           "Cabinet D'AVOCATS MOREAU", "BNP PARIBAS", "sncf", "Doctor Who", "UP", "LA POSTE", "Ikea", "unknown",
           "DOCTEUR  JEAN-MARC LÉVÊQUE", "Engie", "Amazon EU S.à r.l.", "O'NEILL & CO", "AXA_FRANCE"]
DETAILS = ["Séances de rééducation genou", "IMPÔT SUR LE REVENU 2024", "Abonnement fibre Freebox Pop", "Facture",
           "EDF", "Repas", "CONTRAT D'ENTRETIEN CHAUDIÈRE", "Paracétamol 0,5 mg", "Retour aspirateur Dyson V8",
           "Facture n° 2024-0012 / réf. ABC_123", "1,5 L d'eau", "Octobre 2026", "aucun", "", "Taxe foncière - Lyon 3e",
           "Very long detail with many words that should be trimmed at the boundary of the filename because it is "
           "way too long pour le nom de fichier et de la", "Consultation du 12/03", "Achat… « spécial » #42 @home",
           "Informations sur transactions", "LOCATION DU MOIS DE MARS ET D'AVRIL", "Frais de port, emballage.",
           "Abonnement - mensuel", "Vaccin anti-grippe", "TVA 3E TRIMESTRE", "de la", "Prêt immobilier n°12345",
           "  espaces   multiples  ", "Clé USB 64 Go", "RDV le 3 mars", "Électricité et gaz", "UP UP UP",
           "Mise à jour - - logiciel", "Assurance habitation 2026-2027", "Chaussures Nike Air Max 90 pointure 42"]
DATES = ["2025-03-14", "2026-11-09", "2026-11-10", "2099-01-01", "aucun", "", "14/03/2025", "2025-02-30",
         "2025-3-14", "2026-09-11", "1999-12-31", " 2024-02-29 ", "2023-02-29"]
AMOUNTS = ["180.00 EUR", "1 234,50 €", "EUR 2.99", "2,99EUR", "$76.07", "76.07", "0.00 EUR", "aucun", "",
           "1.234.567,89 EUR", "-45.80 EUR", "12 USD", "£9.99", "¥1200", "45,8 eur", "1'250.00 CHF", "abc",
           "45.80 EUR", "1 050,00 €", "TTC 99,90 EUR", "3.5 GBP", "100 CHF", "7,", "0,01 €"]
ORIGS = ["Scan 20261109-140943.pdf", "2024-01-05 - Ancien nom.pdf", "2024-01-05-x.pdf", "doc.final.pdf",
         "Capture d’écran 2026-11-09 à 10.02.26.png", "IMG_1234.HEIC", "2023-07-01 -Truc.jpg", "facture.pdf"]
CAPTURES = [None, None, "2026-11-09", "2025-06-01"]


def response(fields):
    return "\n".join(f"{k}: {v}" for k, v in fields.items())


cases = []
for _ in range(1500):
    fields = {"type": rng.choice(TYPES), "issuer": rng.choice(ISSUERS), "date": rng.choice(DATES),
              "detail": rng.choice(DETAILS), "amount": rng.choice(AMOUNTS)}
    orig, cap = rng.choice(ORIGS), rng.choice(CAPTURES)
    cases.append({"fields": fields, "original": orig, "capture": cap,
                  "expected": pn.build_filename(response(fields), orig, cap)})

STRINGS = sorted(set(TYPES + ISSUERS + DETAILS + [
    "LE BON COIN", "DU PAIN ET DES JEUX", "SNCF VOYAGEURS", "ÉLECTRICITÉ DE FRANCE", "AU-DELÀ DU RÉEL",
    "D'", "L'ART-DE-VIVRE", "-TIRET-", "X", "ABC DEF", "MAIF ASSURANCES", "Orange SA", "ÉCOLE PRIMAIRE DE LA VILLE"]))
fix_case = [{"s": s, "sentence": se, "expected": pn._fix_case(s, sentence=se)} for s in STRINGS for se in (False, True)]
sanitize = [{"s": s, "expected": pn._sanitize(s)} for s in STRINGS]
parse_amount = [{"s": s, "expected": pn._parse_amount(s)} for s in AMOUNTS + [
    "1 234 567", "12", "-", "€", "USD", "9,999.99 USD", "45.80EUR", "1.5", "0", "12,345", "12.3456 EUR"]]
trim = [{"s": s, "limit": n, "expected": pn._trim_words(s, n)} for s in DETAILS for n in (0, 5, 12, 25, 60)]

# Candidate texts: invoice-like snippets assembled at random.
TOKENS = ["Total TTC", "45,80 €", "1 234,56", "1 234,56 €", "1 050,00", "Le 1er janvier 2025",
          "12 févr. 2024", "03/04/25", "31/02/2024", "2026-12-25", "2099-01-01", "MONTANT DES HONORAIRES 1050",
          "US$ 12.00", "$5.99", "CHF 100.00", "Net à payer : 2 300", "TVA 20%", "12.50%", "Date: 14.03.2025",
          "0,00 €", "Facture", "n° 2024-0012", "Client", "Payé par carte", "15 AOÛT 2026", "3 Décembre 2025",
          "1.234.567,89", "GBP 9.99", "£3.50", "¥1200", "réglé le 05/11/2026", "Solde 99.90", "2,5", "10/11/2026",
          "Échéance 30/11/2026", "Somme due 120", "TTC: 1 200,00 EUR", "Prix 19.99 USD", "\n", "\n", " ", " "]
texts = ["".join(rng.choice(TOKENS) + rng.choice([" ", "\n", " : ", ", "]) for _ in range(rng.randint(1, 25)))
         for _ in range(400)]
date_candidates = [{"text": t, "expected": pn.date_candidates(t)} for t in texts]
amount_candidates = [{"text": t, "expected": pn.amount_candidates(t)} for t in texts]

out = {
    "today": TODAY.isoformat(),
    "instructions": pn.INSTRUCTIONS,
    "image_instructions": pn.IMAGE_INSTRUCTIONS,
    "types": pn.TYPES,
    "image_types": pn.IMAGE_TYPES,
    "build_filename": cases,
    "fix_case": fix_case,
    "sanitize": sanitize,
    "parse_amount": parse_amount,
    "trim_words": trim,
    "date_candidates": date_candidates,
    "amount_candidates": amount_candidates,
}
dest = os.path.join(os.path.dirname(__file__), "..", "Tests", "PDFNamerCoreTests", "Fixtures", "parity.json")
with open(dest, "w") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print(f"{len(cases)} build_filename, {len(fix_case)} fix_case, {len(texts)} texts → {os.path.normpath(dest)}")
