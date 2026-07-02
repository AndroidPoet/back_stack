import nextra from 'nextra'

const withNextra = nextra({
  theme: 'nextra-theme-docs',
  themeConfig: './theme.config.jsx',
  // flexsearch works fine with a static export.
  flexsearch: true,
  defaultShowCopyCode: true,
})

// On GitHub Pages the site is served from /<repo> (e.g. /back_stack). The Pages
// workflow sets PAGES_BASE_PATH; local dev leaves it empty.
const basePath = process.env.PAGES_BASE_PATH || ''

export default withNextra({
  output: 'export',
  images: { unoptimized: true },
  basePath,
  trailingSlash: true,
  env: { NEXT_PUBLIC_BASE_PATH: basePath },
})
