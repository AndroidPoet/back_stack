const config = {
  logo: (
    <span style={{ fontWeight: 700 }}>
      back_stack <span style={{ opacity: 0.6, fontWeight: 400 }}>· you own the back stack</span>
    </span>
  ),
  project: {
    link: 'https://github.com/AndroidPoet/back_stack',
  },
  docsRepositoryBase: 'https://github.com/AndroidPoet/back_stack/tree/main/site',
  footer: {
    text: (
      <span>
        MIT · back_stack — navigation is a List you own ·{' '}
        <a href="https://pub.dev/packages/back_stack" target="_blank" rel="noreferrer">
          pub.dev
        </a>
      </span>
    ),
  },
  head: (
    <>
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <meta
        name="description"
        content="back_stack — the Jetpack Compose Nav3 'you own the back stack' model for Flutter. Navigation is a typed List you push and pop."
      />
    </>
  ),
  useNextSeoProps() {
    return { titleTemplate: '%s – back_stack' }
  },
  primaryHue: 245,
  sidebar: {
    defaultMenuCollapseLevel: 1,
  },
}

export default config
