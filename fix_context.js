const fs = require('fs');
const path = require('path');

function walk(dir) {
    let results = [];
    const list = fs.readdirSync(dir);
    list.forEach(function(file) {
        file = dir + '/' + file;
        const stat = fs.statSync(file);
        if (stat && stat.isDirectory()) { 
            results = results.concat(walk(file));
        } else { 
            if (file.endsWith('.dart')) results.push(file);
        }
    });
    return results;
}

const files = walk('./lib');
files.forEach(f => {
    let raw = fs.readFileSync(f, 'utf8');
    let oldRaw = raw;
    raw = raw.replace(/AppTheme\.([A-Za-z]+)\(context\)/g, 'AppTheme.$1()');
    raw = raw.replace(/AppTheme\.([A-Za-z]+)\(context, /g, 'AppTheme.$1(');
    if (raw !== oldRaw) {
        fs.writeFileSync(f, raw, 'utf8');
        console.log('Fixed: ' + f);
    }
});
