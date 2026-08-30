const fs = require('fs');
const path = require('path');

// 1. Load translations.js
const translationsFile = fs.readFileSync(path.join(__dirname, '../translations.js'), 'utf8');

// Use a function to extract the object using a more flexible method
function extractTranslations(content) {
    // This regex looks for the object assigned to 'const translations ='
    // We'll use 'eval' on the object literal part, which is generally fine for this audit script
    const match = content.match(/const translations\s*=\s*({[\s\S]*?});/);
    if (!match) return null;

    try {
        // Wrap in parentheses to make it an expression and eval it
        return eval('(' + match[1] + ')');
    } catch (e) {
        console.error('Eval failed:', e.message);
        return null;
    }
}

const translations = extractTranslations(translationsFile);
if (!translations) {
    console.error('FAILED: Could not parse translations.js');
    process.exit(1);
}

const locales = ['nl', 'en', 'fr'];
const masterLocale = 'nl';
const otherLocales = locales.filter(l => l !== masterLocale);

console.log('--- TASK 6: TRANSLATION PARITY AUDIT ---');

let missingKeysTotal = 0;
let results = {
    totals: {},
    missing: {},
    orphans: {}
};

locales.forEach(lang => {
    results.totals[lang] = Object.keys(translations[lang]).length;
});

const masterKeys = Object.keys(translations[masterLocale]);

otherLocales.forEach(lang => {
    const langKeys = Object.keys(translations[lang]);
    results.missing[lang] = masterKeys.filter(k => !langKeys.includes(k));
    results.orphans[lang] = langKeys.filter(k => !masterKeys.includes(k));
    missingKeysTotal += results.missing[lang].length;
});

console.log('\nA. KEY TOTALS:');
locales.forEach(lang => {
    console.log(`   - ${lang.toUpperCase()}: ${results.totals[lang]} keys`);
});

console.log('\nB. PARITY GAPS:');
otherLocales.forEach(lang => {
    if (results.missing[lang].length > 0) {
        console.log(`   [${lang.toUpperCase()}] Missing (${results.missing[lang].length}): ${results.missing[lang].join(', ')}`);
    } else {
        console.log(`   [${lang.toUpperCase()}] 100% Parity with ${masterLocale.toUpperCase()}`);
    }
});

if (Object.values(results.orphans).some(o => o.length > 0)) {
    console.log('\nC. ORPHAN KEYS (Exists in FR/EN but not in NL):');
    otherLocales.forEach(lang => {
        if (results.orphans[lang].length > 0) {
            console.log(`   [${lang.toUpperCase()}] Orphans: ${results.orphans[lang].join(', ')}`);
        }
    });
}

// 2. Hardcoded String Audit
console.log('\nD. HARDCODED STRING AUDIT (UI SCAN):');
const filesToAudit = [
    'PV.html',
    'klantenportaalpv.html',
    'onderaannemerA.html',
    'index.html',
    'driver-accept.html',
    'driver-decline.html',
    'reset-password.html',
    'PV-premium-vloot.html',
    'PV-vaste-prijzen.html',
    'PV_Exclusieve_Service.html',
    'PV_Events_Gala.html',
    'PV_Koeriersdienst.html',
    'PV_Luchthavenvervoer.html',
    'PV_Zakelijk_Vervoer.html',
    'PVfaq.html',
    'PVprivacy.html',
    'PValgemene-voorwaarden.html',
    'PVcookiebeleid.html',
    'admin-index.html'
];

let hardcodedFindings = 0;
filesToAudit.forEach(file => {
    const filePath = path.join(__dirname, '..', file);
    if (!fs.existsSync(filePath)) return;

    const content = fs.readFileSync(filePath, 'utf8');

    const bodyMatch = content.match(/<body[\s\S]*?>([\s\S]*?)<\/body>/);
    if (!bodyMatch) return;

    let bodyContent = bodyMatch[1]
        .replace(/<script[\s\S]*?<\/script>/g, '')
        .replace(/<style[\s\S]*?<\/style>/g, '')
        .replace(/<!--[\s\S]*?-->/g, ''); // remove comments

    // Improved heuristic: find text content that looks like Dutch/English/French words
    // and is not inside a tag that has data-i18n
    const lines = bodyContent.split('\n');
    let fileFindings = [];
    lines.forEach((line, index) => {
        const trimmed = line.trim();
        if (!trimmed) return;

        // Skip lines that have common i18n markers or are purely icons/attributes
        if (trimmed.includes('data-i18n') || trimmed.includes('i18n.t') || trimmed.includes('i18n.translations')) return;
        if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
            // Check if it's a tag with text content like <h1>Text</h1>
            const tagWithText = trimmed.match(/<[a-z0-9]+[^>]*>([^<]+)<\/[a-z0-9]+>/i);
            if (tagWithText) {
                const text = tagWithText[1].trim();
                if (shouldFlag(text)) {
                    fileFindings.push(`Line ${index + 1}: "${text}" (in ${trimmed.substring(0, 20)}...)`);
                }
            }
            return;
        }

        // Just raw text on the line
        const rawText = trimmed.replace(/<[^>]+>/g, '').trim();
        if (shouldFlag(rawText)) {
            fileFindings.push(`Line ${index + 1}: "${rawText}"`);
        }
    });

    if (fileFindings.length > 0) {
        console.log(`   [${file}] Potential hardcoded strings:`);
        fileFindings.forEach(f => console.log(`      - ${f}`));
        hardcodedFindings += fileFindings.length;
    } else {
        console.log(`   [${file}] Clean.`);
    }
});

function shouldFlag(text) {
    if (!text || text.length < 3) return false;
    // Ignore common technical terms, codes, and brands
    const ignoreList = [
        'Taxi', 'FleetConnect', 'Fleet Connect', 'App', 'GSM', 'BTW', 'ID', 'PDF', 'CSV', 'JSON',
        'Stripe', 'Stripe Invoice', 'Ryz3n', 'Horizon Of Infinity', 'Digital Supremacy',
        'Control Panel', 'Taxi & Dispatch', 'Logistiek & Supply Chain', 'Legal & Privacy',
        'Immobiliën Verhuur'
    ];
    if (ignoreList.some(term => text.includes(term))) return false;

    // Check if it contains mostly letters and spaces
    return /^[A-Z]/.test(text) && /[a-z]/.test(text) && !text.includes('=>') && !text.includes('{');
}

console.log('\n--- SUMMARY ---');
console.log(`Missing Keys: ${missingKeysTotal}`);
console.log(`Hardcoded Findings: ${hardcodedFindings}`);
console.log(`Recommendation: ${missingKeysTotal === 0 && hardcodedFindings === 0 ? 'PASS' : 'FAIL'}`);

if (missingKeysTotal > 0 || hardcodedFindings > 0) {
    // We won't exit with error here so we can see the results in one go and then fix
    // process.exit(1);
}
process.exit(0);
