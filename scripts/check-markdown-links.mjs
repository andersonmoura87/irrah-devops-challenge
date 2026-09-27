// Dependency-free check of local file/directory destinations, not URL or anchor validation.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export function localLinks(markdown) {
  const links = [];
  let fence;
  for (const [index, raw] of markdown.split(/\r?\n/).entries()) {
    const marker = raw.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) fence = undefined;
      continue;
    }
    if (marker) { fence = marker[1]; continue; }
    if (/^( {4}|\t)/.test(raw)) continue;
    const line = raw.replace(/(`+).*?\1/g, match => ' '.repeat(match.length));
    // Inline links/images (including one level of parentheses) and reference definitions.
    const inline = /!?\[[^\]\n]*\]\(\s*(?:<([^>\n]*)>|((?:\\.|[^()\s\\]|\([^()\n]*\))*))(?:[ \t]+(?:"[^"\n]*"|'[^'\n]*'|\([^\)\n]*\)))?\s*\)/g;
    const definition = line.match(/^ {0,3}\[[^\]\n]+\]:\s*(?:<([^>\n]+)>|(\S+))/);
    const destinations = [...line.matchAll(inline)].map(match => match[1] ?? match[2]);
    if (definition) destinations.push(definition[1] ?? definition[2]);
    for (const target of destinations) {
      if (!target || target.startsWith('#') || target.startsWith('//') || /^[a-z][a-z\d+.-]*:/i.test(target)) continue;
      links.push({ target, line: index + 1 });
    }
  }
  return links;
}

export function checkLinks(markdown, file, files) {
  return localLinks(markdown).flatMap(({ target, line }) => {
    let decoded;
    try {
      decoded = decodeURIComponent(target.split(/[?#]/, 1)[0]).replace(/\\([() ])/g, '$1');
    } catch {
      return [`${file}:${line}: invalid URL encoding: ${target}`];
    }
    const destination = path.posix.normalize(decoded.startsWith('/')
      ? decoded.slice(1)
      : path.posix.join(path.posix.dirname(file), decoded)).replace(/\/+$/, '') || '.';
    const outside = destination === '..' || destination.startsWith('../');
    const exists = destination === '.' || files.has(destination) || [...files].some(name => name.startsWith(`${destination}/`));
    return outside || !exists ? [`${file}:${line}: local destination absent from repository files: ${target}`] : [];
  });
}

function main() {
  const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  // Include new, non-ignored files before git add; exclude caches, secrets and evidence.
  const listing = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root, encoding: 'utf8' });
  const files = new Set(listing.split('\0').filter(file => file && existsSync(path.join(root, file))));
  const markdownFiles = [...files].filter(file => /\.md$/i.test(file)).sort();
  let count = 0;
  const errors = [];
  for (const file of markdownFiles) {
    const markdown = readFileSync(path.join(root, file), 'utf8');
    count += localLinks(markdown).length;
    errors.push(...checkLinks(markdown, file, files));
  }
  for (const error of errors) console.error(error);
  console.log(`${markdownFiles.length} Markdown files; ${count} local links; ${errors.length} errors (external URLs/anchors not checked).`);
  if (errors.length) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main();
