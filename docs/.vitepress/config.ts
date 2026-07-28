import { defineConfig } from 'vitepress'

export default defineConfig({
  base: '/daho/',
  title: 'Daho',
  description: 'Fast HTTP framework for Dart backed by a native H2O server',
  lang: 'en-US',
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['meta', { name: 'theme-color', content: '#4f46e5' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'Daho — Fast HTTP Framework for Dart' }],
    ['meta', { property: 'og:description', content: 'Backed by a native H2O server via FFI. Express-style API. Multi-core out of the box.' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
  ],
  themeConfig: {
    logo: false,
    siteTitle: 'Daho',
    nav: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting Started', link: '/guide/getting-started' },
          { text: 'Configuration', link: '/guide/configuration' },
          { text: 'Routing', link: '/guide/routing' },
          { text: 'Middleware', link: '/guide/middleware' },
          { text: 'Request & Response', link: '/guide/request-response' },
        ],
      },
      {
        text: 'Ecosystem',
        items: [
          { text: 'Authentication', link: '/guide/authentication' },
          { text: 'Templates (Clurit)', link: '/guide/templates' },
          { text: 'CLI', link: '/guide/cli' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'API Reference', link: '/api/' },
          { text: 'Examples', link: '/guide/examples' },
          { text: 'Deployment', link: '/guide/deployment' },
        ],
      },
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          collapsed: false,
          items: [
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Configuration', link: '/guide/configuration' },
            { text: 'CLI', link: '/guide/cli' },
          ],
        },
        {
          text: 'Core Concepts',
          collapsed: false,
          items: [
            { text: 'Routing', link: '/guide/routing' },
            { text: 'Middleware', link: '/guide/middleware' },
            { text: 'Request & Response', link: '/guide/request-response' },
            { text: 'Static Files', link: '/guide/static-files' },
            { text: 'Error Handling', link: '/guide/error-handling' },
          ],
        },
        {
          text: 'Ecosystem',
          collapsed: false,
          items: [
            { text: 'Authentication', link: '/guide/authentication' },
            { text: 'Templates (Clurit)', link: '/guide/templates' },
          ],
        },
        {
          text: 'Going to Production',
          collapsed: false,
          items: [
            { text: 'Testing', link: '/guide/testing' },
            { text: 'Deployment', link: '/guide/deployment' },
            { text: 'Performance', link: '/guide/performance' },
          ],
        },
        {
          text: 'Reference',
          collapsed: false,
          items: [
            { text: 'Examples', link: '/guide/examples' },
            { text: 'API Reference', link: '/api/' },
          ],
        },
      ],
      '/api/': [
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/api/' },
            { text: 'Daho', link: '/api/#daho' },
            { text: 'DahoGroup', link: '/api/#dahogroup' },
            { text: 'DahoConfig', link: '/api/#dahoconfig' },
            { text: 'DahoRequest', link: '/api/#dahorequest' },
            { text: 'DahoResponse', link: '/api/#dahoresponse' },
            { text: 'Middlewares', link: '/api/#middlewares' },
            { text: 'Typedefs', link: '/api/#typedefs' },
          ],
        },
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/burhanwakhid/daho' },
    ],
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2025-present Daho contributors',
    },
    search: {
      provider: 'local',
    },
    editLink: {
      pattern: 'https://github.com/burhanwakhid/daho/edit/master/docs/:path',
      text: 'Edit this page on GitHub',
    },
    docFooter: {
      prev: 'Previous',
      next: 'Next',
    },
    outline: {
      level: [2, 3],
      label: 'On this page',
    },
  },
})
