import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Daho',
  description: 'Fast HTTP framework for Dart backed by native H2O server',
  head: [
    ['meta', { name: 'theme-color', content: '#2563eb' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'Daho — Fast HTTP Framework for Dart' }],
    ['meta', { property: 'og:description', content: 'Backed by native H2O server via FFI. Express-style API. Multi-core out of the box.' }],
  ],
  themeConfig: {
    logo: false,
    siteTitle: 'Daho',
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'API Reference', link: '/api/' },
      { text: 'Examples', link: '/guide/examples' },
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Configuration', link: '/guide/configuration' },
          ],
        },
        {
          text: 'Core Concepts',
          items: [
            { text: 'Routing', link: '/guide/routing' },
            { text: 'Middleware', link: '/guide/middleware' },
            { text: 'Request & Response', link: '/guide/request-response' },
            { text: 'Static Files', link: '/guide/static-files' },
          ],
        },
        {
          text: 'Advanced',
          items: [
            { text: 'Testing', link: '/guide/testing' },
            { text: 'Examples', link: '/guide/examples' },
          ],
        },
      ],
      '/api/': [
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/api/' },
          ],
        },
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/burhanwakhid/daho' },
    ],
    footer: {
      message: 'Released under the MIT License.',
    },
    search: {
      provider: 'local',
    },
    editLink: {
      pattern: 'https://github.com/burhanwakhid/daho/edit/main/docs/:path',
    },
  },
})
