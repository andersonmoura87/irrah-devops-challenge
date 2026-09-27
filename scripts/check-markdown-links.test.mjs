import assert from 'node:assert/strict';
import test from 'node:test';
import { checkLinks, localLinks } from './check-markdown-links.mjs';

const files = new Set(['README.md', 'docs/guide.md', 'docs/space name.md', 'docs/diagram(1).svg', 'terraform/main.tf']);

test('relative paths, root paths, images, titles and reference definitions', () => {
  const markdown = [
    '[readme](../README.md)',
    '[root](/README.md)',
    '![image](diagram(1).svg "diagram")',
    '[space](<space name.md>)',
    '[encoded](space%20name.md)',
    '[reference]: ../terraform/main.tf "Terraform"',
    '[directory](../terraform/)',
    '[`inline code label`](../README.md)',
  ].join('\n');
  assert.equal(localLinks(markdown).length, 8);
  assert.deepEqual(checkLinks(markdown, 'docs/guide.md', files), []);
});

test('missing local file fails with source and line', () => {
  assert.deepEqual(checkLinks('text\n[missing](absent.md)', 'docs/guide.md', files), [
    'docs/guide.md:2: local destination absent from repository files: absent.md',
  ]);
});

test('external URLs, anchors and code examples are not local file checks', () => {
  const markdown = [
    '[web](https://example.invalid/path)', '[mail](mailto:user@example.invalid)',
    '[cdn](//example.invalid/path)', '[anchor](#section)',
    '`[example](missing.md)`', '    [indented](missing.md)',
    '```markdown', '[fenced](missing.md)', '```',
    '~~~~', '[fenced](missing.md)', '~~~~',
  ].join('\n');
  assert.deepEqual(localLinks(markdown), []);
});

test('file fragments and query strings check only the file destination', () => {
  assert.deepEqual(checkLinks('[ref](../README.md?raw=1#context)', 'docs/guide.md', files), []);
});

test('outside paths and malformed encoding fail', () => {
  assert.equal(checkLinks('[outside](../../private.md)', 'docs/guide.md', files).length, 1);
  assert.equal(checkLinks('[encoding](bad%ZZ.md)', 'docs/guide.md', files).length, 1);
});

test('case mismatches and ignored/local-only targets cannot pass on one OS only', () => {
  assert.equal(checkLinks('[case](../readme.md)', 'docs/guide.md', files).length, 1);
  assert.equal(checkLinks('[ignored](../.local/private.md)', 'docs/guide.md', files).length, 1);
});
