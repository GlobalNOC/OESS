<?xml version='1.0'?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:fo="http://www.w3.org/1999/XSL/Format"
    version="1.0">

<xsl:import href="http://docbook.sourceforge.net/release/xsl/1.75.2//html/chunk.xsl"/>

<xsl:param name="html.stylesheet" select="'bsd_docbook.css'"/>
<xsl:param name="admon.graphics" select="1"/>

<xsl:param name="ignore.image.scaling" select="1"/>

<xsl:template name="user.footer.navigation">
  <xsl:apply-templates select="//copyright[1] " mode="titlepage.mode"/>

</xsl:template>

<!-- from onechunk.xsl to chunk into one file so its much easier to have external hyperlinks to documentation -->
<xsl:param name="onechunk" select="1"/>
<xsl:param name="suppress.navigation">1</xsl:param>

<xsl:template name="href.target.uri">
  <xsl:param name="object" select="."/>
  <xsl:text>#</xsl:text>
  <xsl:call-template name="object.id">
    <xsl:with-param name="object" select="$object"/>
  </xsl:call-template>
</xsl:template>

</xsl:stylesheet>
