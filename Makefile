OUTFILE= Alfred-Coffee.alfredworkflow
INFILES= coffee.pl \
	 coffee.png \
	 decaf.png \
	 EE620B09-FD6F-4626-AF43-718D5B9AE9E0.png \
	 icon.png \
	 info.plist

$(OUTFILE): $(INFILES)
	$(RM) $(OUTFILE)
	zip $(OUTFILE) $(INFILES)
