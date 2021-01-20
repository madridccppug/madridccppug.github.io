set -x
docker run --rm -it --volume="$PWD:/srv/jekyll" -p 4000:4000 jekyll/jekyll bash tools/run.sh --docker
