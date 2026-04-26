import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  integrations: [
    starlight({
      title: 'silva-omnium',
      description: '모든 것이 쌓이는 개인 숲',
    }),
  ],
});
