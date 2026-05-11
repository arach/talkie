import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import ssh2 from 'ssh2';

const { Server } = ssh2;

const __dirname = dirname(fileURLToPath(import.meta.url));
const fixtureRoot = join(__dirname, '.data');
const hostKeyPath = join(fixtureRoot, 'host_key');

const host = process.env.TALKIE_SSH_FIXTURE_HOST ?? '127.0.0.1';
const port = Number.parseInt(process.env.TALKIE_SSH_FIXTURE_PORT ?? '2222', 10);
const username = process.env.TALKIE_SSH_FIXTURE_USERNAME ?? 'talkie';
const password = process.env.TALKIE_SSH_FIXTURE_PASSWORD ?? 'talkie-demo';

mkdirSync(fixtureRoot, { recursive: true });

if (!existsSync(hostKeyPath)) {
  execFileSync('ssh-keygen', ['-t', 'ed25519', '-N', '', '-f', hostKeyPath], { stdio: 'ignore' });
}

const prompt = `${username}@fixture:~$ `;
const hostKey = readFileSync(hostKeyPath);

function writePrompt(stream) {
  stream.write(prompt);
}

function writeBanner(stream) {
  stream.write('\u001b[32mTalkie SSH fixture ready\u001b[0m\r\n');
  stream.write('Password auth and PTY shell are working.\r\n');
  writePrompt(stream);
}

function handleCommand(command, stream) {
  switch (command.trim()) {
  case '':
    break;
  case 'exit':
    stream.exit(0);
    stream.end();
    return;
  case 'pwd':
    stream.write('/Users/talkie\r\n');
    break;
  case 'whoami':
    stream.write(`${username}\r\n`);
    break;
  default:
    stream.write(`echo: ${command.trim()}\r\n`);
    break;
  }

  writePrompt(stream);
}

const server = new Server({ hostKeys: [hostKey] }, (client) => {
  client
    .on('authentication', (context) => {
      if (context.method === 'password' && context.username === username && context.password === password) {
        context.accept();
        return;
      }

      context.reject(['password']);
    })
    .on('ready', () => {
      client.on('session', (accept) => {
        const session = accept();

        session.on('pty', (acceptPty) => {
          acceptPty();
        });

        session.on('window-change', (acceptWindowChange) => {
          if (acceptWindowChange) {
            acceptWindowChange();
          }
        });

        session.on('shell', (acceptShell) => {
          const stream = acceptShell();
          let currentLine = '';

          writeBanner(stream);

          stream.on('data', (chunk) => {
            const text = chunk.toString('utf8');

            for (const character of text) {
              if (character === '\u0003') {
                currentLine = '';
                stream.write('^C\r\n');
                writePrompt(stream);
                continue;
              }

              if (character === '\u007f') {
                if (currentLine.length > 0) {
                  currentLine = currentLine.slice(0, -1);
                  stream.write('\b \b');
                }
                continue;
              }

              if (character === '\r') {
                stream.write('\r\n');
                handleCommand(currentLine, stream);
                currentLine = '';
                continue;
              }

              if (character === '\n') {
                continue;
              }

              currentLine += character;
              stream.write(character);
            }
          });
        });
      });
    });
});

server.listen(port, host, () => {
  console.log(`Talkie SSH fixture listening on ssh://${username}@${host}:${port}`);
  console.log(`Password: ${password}`);
});

const shutdown = () => {
  server.close(() => process.exit(0));
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
