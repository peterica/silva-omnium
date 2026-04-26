import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader({
      pattern: [
        '**/*.{md,mdx}',
        '!**/_meta/**',
        '!**/.obsidian/**',
        '!**/_attachments/**',
      ],
    }),
    schema: docsSchema({
      extend: z.object({
        aliases: z.array(z.string()).optional(),
        category: z.string().optional(),
        src: z.array(z.string()).optional(),
        tags: z.array(z.string()).optional(),
        updated: z.union([z.string(), z.date()]).optional(),
        status: z.enum(['draft', 'stable']).optional(),
      }),
    }),
  }),
};
