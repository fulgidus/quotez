/**
 * QOTD TCP Client Module
 * Implements RFC 865 Quote of the Day protocol client
 */

const TIMEOUT_MS = 5000; // 5 second timeout

interface SocketData {
  chunks: Buffer[];
  resolve: (value: string) => void;
  reject: (error: Error) => void;
  timeoutId?: Timer;
}

/**
 * Fetch a quote from a QOTD TCP service
 * @param host QOTD service hostname or IP address
 * @param port QOTD service TCP port
 * @returns Quote text (trimmed), or throws error on failure
 * @throws Error with descriptive message on connection failure, timeout, or empty response
 */
export async function getQuote(host: string, port: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const socketData: SocketData = {
      chunks: [],
      resolve,
      reject,
    };

    // Set timeout for the entire operation
    socketData.timeoutId = setTimeout(() => {
      reject(new Error(`Connection timeout after ${TIMEOUT_MS}ms`));
    }, TIMEOUT_MS);

    Bun.connect({
      hostname: host,
      port: port,
      socket: {
        open() {
          // Connection established, waiting for data
        },

        data(socket, data) {
          // Accumulate received data chunks
          socketData.chunks.push(Buffer.from(data));
        },

        end(socket) {
          // Server closed connection (normal for QOTD protocol)
          clearTimeout(socketData.timeoutId);

          // Concatenate all chunks and convert to string
          const fullData = Buffer.concat(socketData.chunks).toString('utf-8');
          const quote = fullData.trim();

          if (quote.length === 0) {
            socketData.reject(new Error('Empty response from QOTD service'));
          } else {
            socketData.resolve(quote);
          }
        },

        close(socket) {
          // Connection closed by client or server
          clearTimeout(socketData.timeoutId);

          // If we haven't resolved yet, check if we have data
          if (socketData.chunks.length > 0) {
            const fullData = Buffer.concat(socketData.chunks).toString('utf-8');
            const quote = fullData.trim();

            if (quote.length === 0) {
              socketData.reject(new Error('Empty response from QOTD service'));
            } else {
              socketData.resolve(quote);
            }
          }
        },

        error(socket, error) {
          // Socket error during communication
          clearTimeout(socketData.timeoutId);
          socketData.reject(
            new Error(`Socket error: ${error.message || 'Unknown error'}`)
          );
        },

        connectError(socket, error) {
          // Failed to establish connection
          clearTimeout(socketData.timeoutId);
          
          // Provide more descriptive error messages
          const errorMessage = error.message || error.code || 'Unknown error';
          if (errorMessage.includes('ECONNREFUSED') || error.code === 'ECONNREFUSED') {
            socketData.reject(
              new Error(`Connection refused: ${host}:${port}`)
            );
          } else if (errorMessage.includes('ETIMEDOUT') || error.code === 'ETIMEDOUT') {
            socketData.reject(
              new Error(`Connection timeout: ${host}:${port}`)
            );
          } else if (errorMessage.includes('EHOSTUNREACH') || error.code === 'EHOSTUNREACH') {
            socketData.reject(
              new Error(`Host unreachable: ${host}:${port}`)
            );
          } else {
            socketData.reject(
              new Error(`Connection failed: ${errorMessage}`)
            );
          }
        },

        timeout(socket) {
          // Connection timeout (Bun's internal timeout)
          clearTimeout(socketData.timeoutId);
          socketData.reject(
            new Error(`Connection timeout: ${host}:${port}`)
          );
        },
      },
    }).catch((error) => {
      // Catch any errors from Bun.connect itself
      clearTimeout(socketData.timeoutId);
      socketData.reject(
        new Error(`Failed to connect: ${error.message || 'Unknown error'}`)
      );
    });
  });
}
