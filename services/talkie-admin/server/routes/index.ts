import { eventHandler, sendRedirect } from 'h3';

export default eventHandler((event) => {
  return sendRedirect(event, '/admin');
});
